classdef tDrugDisposition_DAR < matlab.unittest.TestCase
    %tDrugDisposition_DAR  What Drug-to-Antibody Ratio guarantees to anyone who uses it.
    %
    %   Drug-to-Antibody Ratio, in DrugDispositionModels.sbproj, computes
    %   the average number of payloads per antibody, Average_DAR, for a
    %   model that otherwise takes it as a constant. Between doses,
    %   Average_DAR decays as the linker deconjugates at k_dc. At each dose,
    %   fresh ADC at DAR_init mixes with the ADC already in circulation,
    %   total_ADC, and Average_DAR resets to their weighted average.
    %
    %   Why test a model? Models in the repository are built to be reused,
    %   by people who did not build them. This test is the model's
    %   contract: each test is one thing the model guarantees, and no
    %   version of the model goes into the repository unless it passes. If
    %   you import Drug-to-Antibody Ratio, you can rely on what is tested
    %   here. If you change it, run the test: a failure means you broke
    %   something someone else may depend on.
    %
    %   Each test is named for its guarantee, so the list of results reads
    %   as the model's specification. There are two kinds:
    %
    %   - Structure: what is in the model. The quantities a parent model
    %     connects to by name: Average_DAR, which it replaces in the parent;
    %     k_dc; total_ADC, which the parent supplies; and the dose schedule,
    %     which it shares with the parent's dose.
    %   - Behavior: what the model does. Run on its own, with the linker
    %     deconjugating: Average_DAR starts at DAR_init, decays at k_dc,
    %     resets at each dose to the weighted average of fresh and
    %     circulating ADC, and resets only for the doses the schedule gives.
    %     Without deconjugation, Average_DAR stays at DAR_init.
    %
    %   runtests("ModelRepository/tests/tDrugDisposition_DAR.m")
    %
    % At the n-th dose, at time n*dose_interval, the reset gives
    %   DAR+ = (DAR_init*dose_amount + DAR-*total_ADC)/(dose_amount + total_ADC),
    % where DAR- is the value just before; in between,
    %   DAR(t) = DAR+*exp(-k_dc*(t - n*dose_interval)).

    properties (Constant)
        MODEL_PROJECT = fullfile(fileparts(fileparts(mfilename("fullpath"))), "DrugDispositionModels.sbproj")
        MODEL_NAME = "Drug-to-Antibody Ratio"
        % What a parent model connects to by name.
        INTERFACE = ["Average_DAR" "k_dc" "total_ADC" "dose_amount" "dose_interval" "dose_repeat"]
        DECONJUGATION_RATE = 0.001  % 1/hour, slow enough that DAR is far from 0 at the next dose
        RESETS = 1                  % doses after the first, for the runs
        TOLERANCE = 1e-6            % relative
    end

    properties (TestParameter)
        quantity = {"Average_DAR", "k_dc", "total_ADC", "dose_amount", "dose_interval", "dose_repeat"}
        % ADC still circulating at each dose: none, or as much as the dose.
        circulating = struct("none", "NoCirculating", "asMuchAsDose", "Circulating")
    end

    properties (Access = private)
        Model           % Drug-to-Antibody Ratio, as saved
        NoDeconjugation % struct of logged columns: as saved, over RESETS + 2 dose intervals
        NoCirculating   % the same, deconjugating at DECONJUGATION_RATE, total_ADC = 0
        Circulating     % the same, with total_ADC = dose_amount
    end

    methods (TestClassSetup)
        function loadAndSimulate(testCase)
            project = sbioloadproject(testCase.MODEL_PROJECT);
            testCase.Model = modelNamed(project, testCase.MODEL_NAME);
            model = configuredCopy(testCase.Model, testCase.RESETS + 2);
            schedule = variantSetting("schedule", "dose_repeat", testCase.RESETS);
            testCase.NoDeconjugation = simulate(model, schedule);
            deconjugation = variantSetting("deconjugation", "k_dc", testCase.DECONJUGATION_RATE);
            testCase.NoCirculating = simulate(model, [schedule, deconjugation]);
            circulating = variantSetting("circulating", "total_ADC", parameterValue(model, "dose_amount"));
            testCase.Circulating = simulate(model, [schedule, deconjugation, circulating]);
        end
    end

    methods (Test)
        % --- structure --------------------------------------------------
        function providesQuantityToConnect(testCase, quantity)
            % A parent model can put it in an equivalence set with its own.
            testCase.verifyNumElements(quantityNamed(testCase.Model, quantity), 1, quantity + " is not in the model");
        end

        function computesAverageDARFromItsState(testCase)
            % Average_DAR is set by a rule, so it can be the resolved
            % quantity for every Average_DAR in a parent model.
            rule = sbioselect(testCase.Model.Rules, "Where", "Rule", "regexp", "^\s*Average_DAR\s*=");
            testCase.verifyNumElements(rule, 1, "Average_DAR must be set by one rule");
            testCase.verifyEqual(string(rule.RuleType), "repeatedAssignment");
        end

        function givesEveryQuantityUnits(testCase)
            % So it can be combined with models in other units.
            model = testCase.Model;
            quantities = [model.Compartments; vertcat(model.Compartments.Species); model.Parameters];
            testCase.verifyEmpty(componentNames(quantities(cellfun(@isempty, {quantities.Units}))), ...
                "These quantities have no units");
        end

        % --- behavior ---------------------------------------------------
        function startsAtDARInit(testCase, circulating)
            c = testCase.(circulating);
            testCase.verifyEqual(c.Average_DAR(1), c.DAR_init(1));
        end

        function staysAtDARInitWithoutDeconjugation(testCase)
            c = testCase.NoDeconjugation;
            testCase.verifyEqual(c.Average_DAR, repmat(c.DAR_init(1), size(c.Average_DAR)), RelTol=1e-12);
        end

        function decaysAtKdcBeforeTheNextDose(testCase, circulating)
            c = testCase.(circulating);
            before = c.time < c.dose_interval(1);
            testCase.verifyEqual(c.Average_DAR(before), c.DAR_init(1)*exp(-c.k_dc(1)*c.time(before)), ...
                RelTol=testCase.TOLERANCE);
        end

        function resetsToWeightedAverageAtEachDose(testCase, circulating)
            % Fresh ADC at DAR_init, weighted by dose_amount, and
            % circulating ADC, weighted by total_ADC.
            c = testCase.(circulating);
            interval = c.dose_interval(1);
            justBefore = c.Average_DAR(c.time == interval - 1)*exp(-c.k_dc(1));
            reset = (c.DAR_init(1)*c.dose_amount(1) + justBefore*c.total_ADC(1))/(c.dose_amount(1) + c.total_ADC(1));
            testCase.verifyEqual(c.Average_DAR(c.time == interval + 1), reset*exp(-c.k_dc(1)), ...
                RelTol=testCase.TOLERANCE);
        end

        function resetsOnlyForScheduledDoses(testCase, circulating)
            % After 1 + dose_repeat doses, Average_DAR keeps decaying.
            c = testCase.(circulating);
            last = (testCase.RESETS + 1)*c.dose_interval(1);
            after = c.time >= last - 1;
            t = c.time(after);
            testCase.verifyEqual(c.Average_DAR(after), c.Average_DAR(find(after, 1))*exp(-c.k_dc(1)*(t - t(1))), ...
                RelTol=testCase.TOLERANCE);
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

function names = componentNames(components)
names = string(get(components, {"Name"}))';
end

% -------------------------------------------------------------------------
% Simulation

function model = configuredCopy(source, intervals)
% A copy to simulate for the given number of dose intervals, on an hourly
% grid, at tight tolerances. The saved model is left as it is.
model = copyobj(source);
cs = getconfigset(model, "active");
cs.StopTime = intervals*parameterValue(model, "dose_interval");
cs.SolverOptions.OutputTimes = 0:1:cs.StopTime;
cs.SolverOptions.RelativeTolerance = 1e-10;
cs.SolverOptions.AbsoluteTolerance = 1e-12;
end

function variant = variantSetting(variantName, parameterName, value)
% A variant, not in the model, setting one of its parameters.
variant = sbiovariant(variantName);
addcontent(variant, {"parameter", parameterName, "Value", value});
end

function columns = simulate(model, variants)
% Time and every compartment, species and parameter, as a struct of columns
% named by full name relative to model, with dots as underscores.
cs = getconfigset(model, "active");
quantities = [model.Compartments; vertcat(model.Compartments.Species); model.Parameters];
cs.RuntimeOptions.StatesToLog = quantities;
res = sbiosimulate(model, cs, variants);
columns = struct("time", res.Time);
for q = quantities'
    [~, data] = selectbyname(res, q.FullyQualifiedName);
    columns.(replace(erase(q.FullyQualifiedName, model.FullyQualifiedName + "."), ".", "_")) = data;
end
end
