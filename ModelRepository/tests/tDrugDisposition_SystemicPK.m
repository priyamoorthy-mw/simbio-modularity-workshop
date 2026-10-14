classdef tDrugDisposition_SystemicPK < matlab.unittest.TestCase
    %tDrugDisposition_SystemicPK  What SystemicPK guarantees to anyone who uses it.
    %
    %   SystemicPK, in DrugDispositionModels.sbproj, is the systemic
    %   pharmacokinetics of an antibody-drug conjugate (ADC) and its free
    %   payload. Each distributes between a central and a peripheral
    %   compartment and permeates into the tumor, and each is eliminated
    %   from the central compartment. If the linker deconjugates (k_dc > 0),
    %   ADC releases Average_DAR payloads per ADC wherever it is. IV_dose
    %   gives dose_amount of ADC into the central compartment, computed
    %   from a dose in mg/kg.
    %
    %   Why test a model? Models in the repository are built to be reused,
    %   by people who did not build them. This test is the model's
    %   contract: each test is one thing the model guarantees, and no
    %   version of the model goes into the repository unless it passes. If
    %   you import SystemicPK, you can rely on what is tested here. If you
    %   change it, run the test: a failure means you broke something
    %   someone else may depend on.
    %
    %   Each test is named for its guarantee, so the list of results reads
    %   as the model's specification. There are two kinds:
    %
    %   - Structure: what is in the model. The quantities a parent model
    %     connects to by name: the tumor and its free ADC and payload, the
    %     ADC's properties, the total systemic ADC, and the dose schedule,
    %     which a model that responds to each dose can share. The dose
    %     defaults to a single administration, and the standalone driver
    %     supplies what a parent model would.
    %   - Behavior: what the model does. Run on its own, under the driver,
    %     with and without deconjugation: ADC leaves only by central
    %     elimination, payload is created only by deconjugation and leaves
    %     only by central elimination, and each administration of IV_dose
    %     adds dose_amount of ADC.
    %
    %   runtests("ModelRepository/tests/tDrugDisposition_SystemicPK.m")

    properties (Constant)
        MODEL_PROJECT = fullfile(fileparts(fileparts(mfilename("fullpath"))), "DrugDispositionModels.sbproj")
        MODEL_NAME = "SystemicPK"
        DRIVER = "Drivers for testing standalone model"
        DOSE = "IV_dose"
        DOSE_TARGET = "Central.A"
        % What a parent model connects to by name.
        INTERFACE = ["Tumor" "Tumor.A" "Tumor.P" "tumor_volume" "epsilon_ADC" "epsilon_payload" ...
            "MOL_UNIT" "Average_DAR" "k_dc" "total_ADC_systemic" "dose_amount" "dose_interval" "dose_repeat"]
        % What the driver supplies in place of a parent model.
        DRIVEN = ["Central.A" "tumor_volume"]
        DECONJUGATION_RATE = 0.01   % 1/hour, for the run with deconjugation
        REPEATS = 2                 % extra administrations, for the dosing run
        TOLERANCE = 1e-6            % relative
        NANOMOLE_PER_MILLIGRAM_PER_GRAM_PER_MOLE = 1e6
    end

    properties (TestParameter)
        quantity = {"Tumor", "Tumor.A", "Tumor.P", "tumor_volume", "epsilon_ADC", "epsilon_payload", ...
            "MOL_UNIT", "Average_DAR", "k_dc", "total_ADC_systemic", "dose_amount", "dose_interval", "dose_repeat"}
        run = struct("noDeconjugation", "NoDeconjugation", "deconjugation", "Deconjugation")
    end

    properties (Access = private)
        Model           % SystemicPK, as saved
        Driver          % its standalone driver
        Dose            % its IV_dose
        NoDeconjugation % struct of logged columns: the driver alone
        Deconjugation   % the same, with the linker deconjugating at DECONJUGATION_RATE
        Dosed           % the driver, with IV_dose given 1 + REPEATS times
    end

    methods (TestClassSetup)
        function loadAndSimulate(testCase)
            project = sbioloadproject(testCase.MODEL_PROJECT);
            testCase.Model = modelNamed(project, testCase.MODEL_NAME);
            testCase.Driver = sbioselect(testCase.Model.Variants, "Name", testCase.DRIVER);
            testCase.assertNumElements(testCase.Driver, 1, "The model must have one variant named " + testCase.DRIVER);
            testCase.Dose = sbioselect(getdose(testCase.Model), "Name", testCase.DOSE);
            testCase.assertNumElements(testCase.Dose, 1, "The model must have one dose named " + testCase.DOSE);

            model = accountingCopy(testCase.Model);
            testCase.NoDeconjugation = simulate(model, testCase.Driver, []);
            deconjugation = sbiovariant("deconjugation");
            addcontent(deconjugation, {"parameter", "k_dc", "Value", testCase.DECONJUGATION_RATE});
            testCase.Deconjugation = simulate(model, [testCase.Driver, deconjugation], []);

            dose = getdose(model, testCase.DOSE);
            repeats = sbiovariant("repeats");
            addcontent(repeats, {"parameter", "dose_repeat", "Value", testCase.REPEATS});
            cs = getconfigset(model, "active");
            cs.StopTime = (testCase.REPEATS + 1)*parameterValue(model, "dose_interval");
            cs.SolverOptions.OutputTimes = 0:1:cs.StopTime;
            testCase.Dosed = simulate(model, [testCase.Driver, repeats], dose);
        end
    end

    methods (Test)
        % --- structure --------------------------------------------------
        function providesQuantityToConnect(testCase, quantity)
            % A parent model can put it in an equivalence set with its own.
            testCase.verifyNumElements(quantityNamed(testCase.Model, quantity), 1, quantity + " is not in the model");
        end

        function dosesCentralADCOnTheSharedSchedule(testCase)
            % IV_dose gives dose_amount into Central.A every dose_interval,
            % dose_repeat more times, so a parent model that shares these
            % parameters sees the same schedule.
            d = testCase.Dose;
            testCase.verifyEqual(string(d.TargetName), testCase.DOSE_TARGET);
            testCase.verifyEqual(string(d.Amount), "dose_amount");
            testCase.verifyEqual(string(d.Interval), "dose_interval");
            testCase.verifyEqual(string(d.RepeatCount), "dose_repeat");
        end

        function dosesOnceByDefault(testCase)
            testCase.verifyEqual(parameterValue(testCase.Model, "dose_repeat"), 0);
        end

        function computesDoseAmountFromMilligramsPerKilogram(testCase)
            % dose_amount, in nanomoles, is dose (mg/kg) times body_mass
            % over the ADC's molecular weight.
            c = initial(testCase.NoDeconjugation);
            testCase.verifyEqual(c.dose_amount, ...
                c.dose*c.body_mass/c.ADC_MW*testCase.NANOMOLE_PER_MILLIGRAM_PER_GRAM_PER_MOLE, RelTol=1e-12);
        end

        function driverSuppliesCentralADCAndTumorVolume(testCase)
            % Apply it to run the model on its own: it supplies the ADC and
            % the tumor volume that a dose and a tumor model would.
            testCase.verifyEqual(sort(drivenNames(testCase.Driver, testCase.Model)), sort(testCase.DRIVEN));
        end

        function givesEveryQuantityUnits(testCase)
            % So it can be combined with models in other units.
            model = testCase.Model;
            quantities = [model.Compartments; vertcat(model.Compartments.Species); model.Parameters];
            testCase.verifyEmpty(componentNames(quantities(cellfun(@isempty, {quantities.Units}))), ...
                "These quantities have no units");
        end

        % --- behavior ---------------------------------------------------
        function eliminatesAtClearanceOverCentralVolume(testCase)
            c = initial(testCase.NoDeconjugation);
            testCase.verifyEqual(c.kel_ADC, c.CL_ADC/c.Vce_ADC, RelTol=1e-12);
            testCase.verifyEqual(c.kel_payload, c.CL_payload/c.Vce_payload, RelTol=1e-12);
        end

        function losesADCOnlyByCentralElimination(testCase, run)
            % Distribution and tumor permeation only move ADC.
            c = testCase.(run);
            total = totalADC(c) + c.Central_A_eliminated;
            testCase.verifyEqual(total, repmat(total(1), size(total)), RelTol=testCase.TOLERANCE);
        end

        function createsPayloadOnlyByDeconjugation(testCase, run)
            % And loses it only by central elimination.
            c = testCase.(run);
            total = c.Central_P + c.Peripheral_P + c.Tumor_P + c.Central_P_eliminated - c.Central_P_released;
            testCase.verifyEqual(total, repmat(total(1), size(total)), ...
                AbsTol=testCase.TOLERANCE*max(c.Central_P_released + 1));
        end

        function releasesAverageDARPayloadsPerADC(testCase)
            % At k_dc per hour, wherever the ADC is.
            c = testCase.Deconjugation;
            rate = c.k_dc(1)*c.Average_DAR(1)/c.MOL_UNIT(1)*totalADC(c);
            released = cumtrapz(c.time, rate);
            testCase.verifyEqual(c.Central_P_released, released, RelTol=1e-4, AbsTol=1e-8);
        end

        function createsNoPayloadWithoutDeconjugation(testCase)
            % k_dc is 0 by default.
            c = testCase.NoDeconjugation;
            testCase.verifyEqual(c.k_dc(1), 0);
            testCase.verifyEqual([c.Central_P c.Peripheral_P c.Tumor_P], zeros(numel(c.time), 3));
        end

        function reportsTotalSystemicADC(testCase)
            % total_ADC_systemic, which a parent model can read, is the ADC
            % in the central and peripheral compartments.
            c = testCase.NoDeconjugation;
            testCase.verifyEqual(c.total_ADC_systemic, c.Central_A + c.Peripheral_A, RelTol=1e-12);
        end

        function addsDoseAmountAtEachAdministration(testCase)
            % 1 + dose_repeat administrations, dose_interval apart, the
            % first at time 0.
            c = testCase.Dosed;
            interval = c.dose_interval(1);
            given = totalADC(c) + c.Central_A_eliminated - driverValue(testCase.Driver, testCase.DOSE_TARGET);
            for n = 1:testCase.REPEATS + 1
                justBefore = c.time == n*interval - 1;
                testCase.verifyEqual(given(justBefore), n*c.dose_amount(1), ...
                    "ADC given before hour " + n*interval, RelTol=testCase.TOLERANCE);
            end
        end
    end
end

% -------------------------------------------------------------------------
% Model inspection

function model = modelNamed(project, name)
values = struct2cell(project);
models = values(cellfun(@(v) isa(v, "SimBiology.Model"), values));
model = models{cellfun(@(m) m.Name == name, models)};
end

function quantity = quantityNamed(model, name)
% The compartment, species or parameter with full name model.name.
quantity = sbioselect(model, "FullyQualifiedName", model.FullyQualifiedName + "." + name);
end

function value = parameterValue(model, name)
value = sbioselect(model.Parameters, "Name", name).Value;
end

function value = driverValue(variant, name)
% The value a variant gives the quantity it names name.
entry = variant.Content{cellfun(@(e) string(e{2}) == name, variant.Content)};
value = entry{4};
end

function names = componentNames(components)
names = string(get(components, {"Name"}))';
end

function names = drivenNames(variant, model)
% The quantities a variant sets, named relative to model; errors on an
% entry naming nothing, which SimBiology would silently ignore.
names = strings(1, numel(variant.Content));
for k = 1:numel(variant.Content)
    entry = variant.Content{k};
    names(k) = entry{2};
    assert(isscalar(sbioselect(model, "Type", entry{1}, "FullyQualifiedName", ...
        model.FullyQualifiedName + "." + names(k))), ...
        "tDrugDisposition_SystemicPK:content", "%s names %s, not in %s", variant.Name, names(k), model.Name);
end
end

% -------------------------------------------------------------------------
% Simulation

function model = accountingCopy(source)
% A copy to simulate on an hourly grid at tight tolerances, in which central
% elimination makes Central.A_eliminated and Central.P_eliminated, and
% deconjugation makes Central.P_released, so ADC and payload can be
% accounted for. Products do not change the rates, which are written out.
% The saved model is left as it is.
model = copyobj(source);
central = sbioselect(model.Compartments, "Name", "Central");
aEliminated = addspecies(central, "A_eliminated", 0, "Units", "nanomole");
pEliminated = addspecies(central, "P_eliminated", 0, "Units", "nanomole");
pReleased = addspecies(central, "P_released", 0, "Units", "nanomole");
addproduct(sbioselect(model.Reactions, "Name", "ADC central elimination"), aEliminated);
addproduct(sbioselect(model.Reactions, "Name", "Payload central elimination"), pEliminated);
for r = sbioselect(model.Reactions, "Where", "Name", "regexp", "^Payload release by deconjugation")'
    addproduct(r, pReleased);
end
cs = getconfigset(model, "active");
cs.SolverOptions.OutputTimes = 0:1:cs.StopTime;
cs.SolverOptions.RelativeTolerance = 1e-10;
cs.SolverOptions.AbsoluteTolerance = 1e-12;
end

function columns = simulate(model, variants, dose)
% Time and every compartment, species and parameter, as a struct of columns
% named by full name relative to model, with dots as underscores.
cs = getconfigset(model, "active");
quantities = [model.Compartments; vertcat(model.Compartments.Species); model.Parameters];
cs.RuntimeOptions.StatesToLog = quantities;
res = sbiosimulate(model, cs, variants, dose);
columns = struct("time", res.Time);
for q = quantities'
    [~, data] = selectbyname(res, q.FullyQualifiedName);
    columns.(replace(erase(q.FullyQualifiedName, model.Name + "."), ".", "_")) = data;
end
end

function values = initial(columns)
values = structfun(@(c) c(1), columns, "UniformOutput", false);
end

function total = totalADC(columns)
% ADC in the central, peripheral and tumor compartments.
total = columns.Central_A + columns.Peripheral_A + columns.Tumor_A;
end
