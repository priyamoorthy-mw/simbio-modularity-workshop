classdef tGenericTumor_Binding < matlab.unittest.TestCase
    %tGenericTumor_Binding  What GenericBinding guarantees to anyone who uses it.
    %
    %   GenericBinding, in GenericTumorCellModels.sbproj, is the binding of
    %   an antibody-drug conjugate (ADC) to its target on one population
    %   of target-expressing (Ag+) cells. Free ADC in the tumor, Tumor.A,
    %   binds the target with one arm and then crosslinks with the second.
    %   Bound ADC is internalized and degraded, which releases its payload,
    %   Average_DAR molecules per ADC, inside the cells
    %   (Tumor.P_int_subtype). The cells' growth and death, which another
    %   model supplies, make and remove target, and dying cells release the
    %   ADC they hold back into the tumor.
    %
    %   Why test a model? Models in the repository are built to be reused,
    %   by people who did not build them. This test is the model's
    %   contract: each test is one thing the model guarantees, and no
    %   version of the model goes into the repository unless it passes. If
    %   you import GenericBinding, you can rely on what is tested here. If
    %   you change it, run the test: a failure means you broke something
    %   someone else may depend on.
    %
    %   Each test is named for its guarantee, so the list of results reads
    %   as the model's specification. There are two kinds:
    %
    %   - Structure: what is in the model. The quantities a parent model
    %     connects to, and the naming that tells you how: quantities shared
    %     with the cells' dynamics and with other populations can be matched
    %     by name, quantities specific to one population end in "subtype",
    %     and every other parameter is internal to the model and tagged
    %     "local". What a parent model supplies is tagged "placeholder",
    %     and the standalone driver supplies it when the model runs alone.
    %   - Behavior: what the model does. Run on its own, under the driver,
    %     with and without deconjugation of the linker: each cell starts
    %     with its targets, total target follows cell turnover, ADC is lost
    %     only by degradation, and payload is released only by degradation
    %     and deconjugation, Average_DAR payloads per ADC.
    %
    %   runtests("ModelRepository/tests/tGenericTumor_Binding.m")
    %
    % Binding and internalization move target between T, AT and ATT (which
    % holds two) and return it to T, so total target
    %   T_total = T + AT + 2*ATT
    % changes only by cell growth and death:
    %   dT_total/dt = growth_rate*receptor_per_cell/N - death_rate*T_total,
    % where N is MOLECULE_PER_NANOMOLE. With the driver's constant rates,
    %   T_total(t) = T_ss + (T_total(0) - T_ss)*exp(-death_rate*t),
    %   T_ss = growth_rate*receptor_per_cell/(N*death_rate).

    properties (Constant)
        MODEL_PROJECT = fullfile(fileparts(fileparts(mfilename("fullpath"))), "GenericTumorCellModels.sbproj")
        MODEL_NAME = "GenericBinding"
        DRIVER = "Drivers for testing standalone model"
        SUBTYPE = "subtype"
        LOCAL_TAG = "local"
        PLACEHOLDER_TAG = "placeholder"
        % What all Ag+ populations share, so a parent model can connect them
        % by name: the tumor and its free ADC and payload, the ADC's
        % properties, and constants.
        SHARED_BY_ALL_POPULATIONS = ["Tumor" "Tumor.A" "Tumor.P" "tumor_volume" "cell_radius" ...
            "epsilon_ADC" "Average_DAR" "k_dc" "kon_3d" "koff" "k_internalization" "k_deg" ...
            "avg_distance_between_arms" "MOL_UNIT" "MOLECULE_PER_NANOMOLE" "PI" "LITER_PER_CUBIC_MICROMETER"]
        % What is specific to this population: the cells it shares with the
        % cells' dynamics, and the target and ADC on them.
        POPULATION_SPECIFIC = ["Tumor.total_cell_subtype" "Tumor.P_int_subtype" "Tumor.ADC_bound_subtype" ...
            "Tumor.T_subtype" "Tumor.AT_subtype" "Tumor.ATT_subtype" "Tumor.A_int_subtype" ...
            "growth_rate_subtype" "death_rate_subtype"]
        % What the driver supplies in place of a parent model.
        DRIVEN = ["Tumor.A" "Tumor.total_cell_subtype" "tumor_volume" "growth_rate_subtype" "death_rate_subtype"]
        DECONJUGATION_RATE = 0.01   % 1/hour, for the run with deconjugation
        TOLERANCE = 1e-6            % relative
    end

    properties (TestParameter)
        quantity = {"Tumor", "Tumor.A", "Tumor.P", "tumor_volume", "cell_radius", "epsilon_ADC", ...
            "Average_DAR", "k_dc", "kon_3d", "koff", "k_internalization", "k_deg", ...
            "avg_distance_between_arms", "MOL_UNIT", "MOLECULE_PER_NANOMOLE", "PI", ...
            "LITER_PER_CUBIC_MICROMETER", "Tumor.total_cell_subtype", "Tumor.P_int_subtype", ...
            "Tumor.ADC_bound_subtype", "growth_rate_subtype", "death_rate_subtype"}
        run = struct("noDeconjugation", "NoDeconjugation", "deconjugation", "Deconjugation")
    end

    properties (Access = private)
        Model           % GenericBinding, as saved
        Driver          % its standalone driver
        NoDeconjugation % struct of logged columns: the driver alone
        Deconjugation   % the same, with the linker deconjugating at DECONJUGATION_RATE
    end

    methods (TestClassSetup)
        function loadAndSimulate(testCase)
            project = sbioloadproject(testCase.MODEL_PROJECT);
            testCase.Model = modelNamed(project, testCase.MODEL_NAME);
            testCase.Driver = sbioselect(testCase.Model.Variants, "Name", testCase.DRIVER);
            testCase.assertNumElements(testCase.Driver, 1, "The model must have one variant named " + testCase.DRIVER);
            model = accountingCopy(testCase.Model);
            testCase.NoDeconjugation = simulate(model, testCase.Driver);
            deconjugation = sbiovariant("deconjugation");
            addcontent(deconjugation, {"parameter", "k_dc", "Value", testCase.DECONJUGATION_RATE});
            testCase.Deconjugation = simulate(model, [testCase.Driver, deconjugation]);
        end
    end

    methods (Test)
        % --- structure --------------------------------------------------
        function providesQuantityToConnect(testCase, quantity)
            % A parent model can put it in an equivalence set with its own.
            testCase.verifyNumElements(quantityNamed(testCase.Model, quantity), 1, quantity + " is not in the model");
        end

        function namesQuantitiesSharedByAllPopulationsWithoutSubtype(testCase)
            % So a parent model can match them by name across populations.
            names = testCase.SHARED_BY_ALL_POPULATIONS;
            testCase.verifyEmpty(names(contains(names, testCase.SUBTYPE)));
        end

        function namesPopulationSpecificQuantitiesSubtype(testCase)
            % So you know not to match them by name across populations.
            names = testCase.POPULATION_SPECIFIC;
            testCase.verifyEmpty(names(~contains(names, testCase.SUBTYPE)));
        end

        function tagsEveryOtherParameterLocal(testCase)
            % A parameter you do not connect is internal to the model. It is
            % tagged local, so you can leave it out when you match
            % quantities, and its name ends in subtype, so that each copy's
            % gets a name of its own when you parameterize it.
            connectable = [testCase.SHARED_BY_ALL_POPULATIONS testCase.POPULATION_SPECIFIC];
            quantities = testCase.Model.Parameters;
            names = relativeNames(testCase.Model, quantities);
            isLocal = arrayfun(@(q) any(string(q.Tags) == testCase.LOCAL_TAG), quantities)';
            testCase.verifyEmpty(names(~ismember(names, connectable) & ~isLocal), ...
                "Neither connectable nor tagged " + testCase.LOCAL_TAG);
            testCase.verifyEmpty(names(ismember(names, connectable) & isLocal), ...
                "Connectable, but tagged " + testCase.LOCAL_TAG);
            testCase.verifyEmpty(names(isLocal & ~endsWith(names, "_" + testCase.SUBTYPE)), ...
                "Tagged " + testCase.LOCAL_TAG + ", but not named for the population");
        end

        function tagsWhatAParentSuppliesPlaceholder(testCase)
            % The driver stands in for these; a parent model must connect
            % them.
            quantities = ownQuantities(testCase.Model);
            names = relativeNames(testCase.Model, quantities);
            isPlaceholder = arrayfun(@(q) any(string(q.Tags) == testCase.PLACEHOLDER_TAG), quantities)';
            testCase.verifyEqual(sort(names(isPlaceholder)), sort(testCase.DRIVEN));
        end

        function driverSuppliesWhatTheCellsAndTumorWould(testCase)
            % Apply it to run the model on its own: it supplies free ADC,
            % and the cells, their growth and death, and the tumor volume
            % that a parent model would.
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
        function startsWithTargetsOnEveryCell(testCase)
            start = initial(testCase.NoDeconjugation);
            testCase.verifyEqual(start.Tumor_T_subtype, ...
                start.Tumor_total_cell_subtype*start.receptor_per_cell_subtype/start.MOLECULE_PER_NANOMOLE, ...
                RelTol=1e-12);
        end

        function totalTargetFollowsCellTurnover(testCase, run)
            c = testCase.(run);
            k = initial(c);
            total = c.Tumor_T_subtype + c.Tumor_AT_subtype + 2*c.Tumor_ATT_subtype;
            steady = k.growth_rate_subtype*k.receptor_per_cell_subtype/(k.MOLECULE_PER_NANOMOLE*k.death_rate_subtype);
            testCase.verifyEqual(total, steady + (total(1) - steady)*exp(-k.death_rate_subtype*c.time), ...
                RelTol=testCase.TOLERANCE);
        end

        function losesADCOnlyByDegradation(testCase, run)
            % Binding, internalization and cell death only move ADC; it
            % leaves only when degraded inside the cells.
            c = testCase.(run);
            total = c.Tumor_A + c.Tumor_AT_subtype + c.Tumor_ATT_subtype + c.Tumor_A_int_subtype + c.Tumor_Degraded;
            testCase.verifyEqual(total, repmat(total(1), size(total)), RelTol=testCase.TOLERANCE);
        end

        function releasesAverageDARPayloadsPerADC(testCase, run)
            % Payload comes only from degraded ADC and, if the linker
            % deconjugates, from ADC still on or in the cells.
            c = testCase.(run);
            k = initial(c);
            released = c.Tumor_P + c.Tumor_P_int_subtype - k.Tumor_P - k.Tumor_P_int_subtype;
            testCase.verifyEqual(released, k.Average_DAR/k.MOL_UNIT*c.Tumor_Degraded + c.Tumor_Deconjugated, ...
                AbsTol=testCase.TOLERANCE*max(abs(released)));
        end

        function releasesPayloadOnlyInsideCellsWithoutDeconjugation(testCase)
            % k_dc is 0 by default: no payload reaches the tumor directly.
            c = testCase.NoDeconjugation;
            testCase.verifyEqual(c.k_dc(1), 0);
            testCase.verifyEqual(c.Tumor_P, repmat(c.Tumor_P(1), size(c.Tumor_P)));
            testCase.verifyGreaterThan(c.Tumor_P_int_subtype(end), 0);
        end

        function reportsADCBoundToThisPopulation(testCase)
            % ADC_bound_subtype, which a parent model can read, is the ADC
            % on and in these cells.
            c = testCase.NoDeconjugation;
            testCase.verifyEqual(c.Tumor_ADC_bound_subtype, ...
                c.Tumor_AT_subtype + c.Tumor_ATT_subtype + c.Tumor_A_int_subtype, RelTol=1e-12);
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

function quantities = ownQuantities(model)
quantities = [model.Compartments; vertcat(model.Compartments.Species); model.Parameters];
end

function names = relativeNames(model, quantities)
% Each quantity's full name, without the model's own name.
names = erase(string(get(quantities, {"FullyQualifiedName"}))', model.FullyQualifiedName + ".");
end

function names = componentNames(components)
names = string(get(components, {"Name"}))';
end

function names = drivenNames(variant, model)
% The quantities a variant sets, by full name relative to model; errors on
% an entry naming nothing, which SimBiology would silently ignore. A species
% may be named without its compartment if no other species has its name.
names = strings(1, numel(variant.Content));
for k = 1:numel(variant.Content)
    entry = variant.Content{k};
    quantity = sbioselect(model, "Type", entry{1}, "FullyQualifiedName", model.FullyQualifiedName + "." + entry{2});
    if isempty(quantity) && entry{1} == "species"
        quantity = sbioselect(model, "Type", "species", "Name", entry{2});
    end
    assert(isscalar(quantity), "tGenericTumor_Binding:content", "%s names %s, not in %s", ...
        variant.Name, entry{2}, model.Name);
    names(k) = erase(string(quantity.FullyQualifiedName), model.FullyQualifiedName + ".");
end
end

% -------------------------------------------------------------------------
% Simulation

function model = accountingCopy(source)
% A copy to simulate on an hourly grid at tight tolerances, in which
% degradation makes Tumor.Degraded and deconjugation makes
% Tumor.Deconjugated, so ADC and payload can be accounted for. Products do
% not change the rates, which are written out. The saved model is left as
% it is.
model = copyobj(source);
tumor = sbioselect(model.Compartments, "Name", "Tumor");
degraded = addspecies(tumor, "Degraded", 0, "Units", "nanomole");
deconjugated = addspecies(tumor, "Deconjugated", 0, "Units", "nanomole");
addproduct(sbioselect(model.Reactions, "Name", "Intracellular ADC degradation"), degraded);
addproduct(sbioselect(model.Reactions, "Name", "Payload release by intracellular deconjugation"), deconjugated);
addproduct(sbioselect(model.Reactions, "Name", "Payload release by deconjugation of bound ADC"), deconjugated);
cs = getconfigset(model, "active");
cs.SolverOptions.OutputTimes = 0:1:cs.StopTime;
cs.SolverOptions.RelativeTolerance = 1e-10;
cs.SolverOptions.AbsoluteTolerance = 1e-14;
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
    columns.(replace(erase(q.FullyQualifiedName, model.Name + "."), ".", "_")) = data;
end
end

function values = initial(columns)
values = structfun(@(c) c(1), columns, "UniformOutput", false);
end
