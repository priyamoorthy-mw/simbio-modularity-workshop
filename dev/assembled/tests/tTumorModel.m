classdef tTumorModel < matlab.unittest.TestCase
    %tTumorModel  What TumorModel guarantees to anyone who uses it.
    %
    %   TumorModel, in dev/TumorModel.sbproj, is the tumor extracted from
    %   ADCBystander in Section 4.3 of the workshop guide. It coordinates
    %   three cell populations from the model repository, AgPosTumor,
    %   AgNegTumor and AgPosStroma: it seeds them from their cell
    %   fractions, computes the tumor volume and the growth rates from all
    %   of them, and shares one tumor, with its free ADC and payload, among
    %   them.
    %
    %   Why test a model? A model that goes into the repository is built to
    %   be reused, by people who did not build it. This test is the model's
    %   contract: each test is one thing the model guarantees. Promote
    %   TumorModel to ModelRepository only with this test, and only once it
    %   passes. If you change the model, run the test: a failure means you
    %   broke something someone else may depend on.
    %
    %   Each test is named for its guarantee, so the list of results reads
    %   as the model's specification. There are two kinds:
    %
    %   - Structure: how the model is put together. Which populations it is
    %     made of, and how they are connected: one tumor, free ADC and
    %     payload, tumor volume and cell geometry for all of them, resolved
    %     in TumorModel; each population's cell counts connected to their
    %     placeholders and resolved in its CellDyn, which owns their
    %     dynamics; and the tumor-wide growth rates connected to each
    %     population they supply. The populations' stand-in rules are off,
    %     the model verifies, and its variants name what they set by full
    %     name, so they apply when TumorModel is simulated on its own.
    %   - Behavior: what the model does on its own, under its driver, in
    %     each of the paper's three scenarios. Each population starts at
    %     its share of the initial tumor, the tumor volume follows all the
    %     cells, ADC is lost only by degradation, payload is released only
    %     from degraded ADC, and every population present is killed.
    %
    %   runtests("dev/tests/tTumorModel.m")

    properties (Constant)
        MODEL_PROJECT = fullfile(fileparts(fileparts(mfilename("fullpath"))), "TumorModel.sbproj")
        MODEL_NAME = "TumorModel"
        POPULATIONS = ["AgPosTumor" "AgNegTumor" "AgPosStroma"]
        AG_POSITIVE = ["AgPosTumor" "AgPosStroma"]
        DRIVER = "Drivers for testing standalone model"
        STANDALONE_RULE = "Rule_tumor_volume_standalone"
        % States shared across the tumor, resolved in TumorModel.
        SHARED = ["Tumor" "Tumor.P" "tumor_volume" "cell_radius" "MOL_UNIT"]
        % Tumor-wide growth rates, and the population quantities they supply.
        GROWTH = struct( ...
            "k_cell_doubling", ["AgPosTumor.CellDyn.k_self_doubling_for_AgPosTumor" ...
                "AgNegTumor.CellDyn.k_self_doubling_for_AgNegTumor"], ...
            "k_recruited_doubling", "AgPosStroma.CellDyn.k_recruited_doubling_for_AgPosStroma", ...
            "Tumor_total_tumor_live_cell", "AgPosStroma.CellDyn.Tumor.total_recruiting_cell_for_AgPosStroma")
        TOLERANCE = 1e-6        % relative
    end

    properties (TestParameter)
        population = {"AgPosTumor", "AgNegTumor", "AgPosStroma"}
        scenario = struct("oneCellType", "One-Cell Type Model", ...
            "independentGrowth", "Independent Growth Bystander Model", ...
            "recruitment", "Recruitment Bystander Model")
    end

    properties (Access = private)
        Model       % TumorModel, as saved
        Resolved    % dictionary: member full name -> resolved quantity's full name
        Runs        % struct, per scenario, of logged columns under the driver
        Unapplied   % struct, per scenario, of the variant's entries that do not apply
    end

    methods (TestClassSetup)
        function loadAndSimulate(testCase)
            testCase.assertTrue(isfile(testCase.MODEL_PROJECT), ...
                "Extract TumorModel and save it as " + testCase.MODEL_PROJECT + " first (Section 4.3).");
            project = sbioloadproject(testCase.MODEL_PROJECT);
            testCase.Model = modelNamed(project, testCase.MODEL_NAME);
            testCase.Resolved = resolvedNames(testCase.Model);
            driver = sbioselect(testCase.Model.Variants, "Name", testCase.DRIVER);
            testCase.assertNumElements(driver, 1, "The model must have one variant named " + testCase.DRIVER);
            model = accountingCopy(testCase.Model, testCase.AG_POSITIVE);
            for name = string(struct2cell(testCase.scenario))'
                variant = sbioselect(model.Variants, "Name", name);
                testCase.assertNumElements(variant, 1, "The model must have one variant named " + name);
                columns = simulate(model, [sbioselect(model.Variants, "Name", testCase.DRIVER), variant]);
                testCase.assertEqual(columns.time(end), getconfigset(model, "active").StopTime, ...
                    "The simulation stopped before StopTime");
                testCase.Runs.(matlab.lang.makeValidName(name)) = columns;
                entries = variantEntries(variant);
                testCase.Unapplied.(matlab.lang.makeValidName(name)) = ...
                    entries(~arrayfun(@(e) appliesTo(testCase.Model, testCase.Resolved, e), entries));
            end
        end
    end

    methods (Test)
        % --- structure --------------------------------------------------
        function isBuiltFromThreeCellPopulations(testCase)
            testCase.verifyEqual(sort(string({testCase.Model.Models.Name})), sort(testCase.POPULATIONS));
        end

        function sharesTumorStatesResolvedInTumorModel(testCase)
            % One tumor, with its free ADC and payload, volume and cell
            % geometry, for every population that uses it.
            for name = testCase.SHARED
                fullName = testCase.MODEL_NAME + "." + name;
                members = membersOf(testCase.Model, testCase.Resolved, fullName);
                testCase.verifyEqual(resolvedName(testCase.Resolved, fullName), fullName, ...
                    name + " must be resolved in TumorModel");
                for p = testCase.POPULATIONS
                    testCase.verifyTrue(any(startsWith(members, testCase.MODEL_NAME + "." + p + ".")), ...
                        name + " must be connected to " + p);
                end
            end
            % Free ADC, for the Ag+ populations, which bind it.
            fullName = testCase.MODEL_NAME + ".Tumor.A";
            members = membersOf(testCase.Model, testCase.Resolved, fullName);
            testCase.verifyEqual(resolvedName(testCase.Resolved, fullName), fullName, "Tumor.A must be resolved in TumorModel");
            for p = testCase.AG_POSITIVE
                testCase.verifyTrue(any(members == testCase.MODEL_NAME + "." + p + ".Binding.Tumor.A"), ...
                    "Tumor.A must be connected to " + p);
            end
        end

        function connectsCellCountsResolvedInCellDynamics(testCase, population)
            % CellDyn owns the dynamics of the cells; TumorModel only sums
            % them.
            names = "Tumor.total_cell_" + population;
            if population ~= "AgPosStroma"
                names = [names "Tumor.live_cell_" + population];
            end
            for name = names
                cellDyn = testCase.MODEL_NAME + "." + population + ".CellDyn." + name;
                placeholder = testCase.MODEL_NAME + "." + name;
                testCase.verifyEqual(resolvedName(testCase.Resolved, placeholder), cellDyn, ...
                    placeholder + " must be connected to, and resolved in, " + population + ".CellDyn");
            end
        end

        function connectsCellFractionResolvedInTumorModel(testCase, population)
            % The scenario variants set the fractions on TumorModel.
            placeholder = testCase.MODEL_NAME + ".cell_fraction_" + population;
            members = membersOf(testCase.Model, testCase.Resolved, placeholder);
            testCase.verifyTrue(any(members == testCase.MODEL_NAME + "." + population + ".CellDyn.cell_fraction_" + population));
            testCase.verifyEqual(resolvedName(testCase.Resolved, placeholder), placeholder);
        end

        function suppliesGrowthRatesToEachPopulation(testCase)
            for rate = string(fieldnames(testCase.GROWTH))'
                fullName = testCase.MODEL_NAME + "." + replace(rate, "Tumor_", "Tumor.");
                members = membersOf(testCase.Model, testCase.Resolved, fullName);
                testCase.verifyEqual(resolvedName(testCase.Resolved, fullName), fullName, ...
                    fullName + " must be resolved in TumorModel, which computes it");
                for supplied = testCase.MODEL_NAME + "." + testCase.GROWTH.(rate)
                    testCase.verifyTrue(any(members == supplied), fullName + " must supply " + supplied);
                end
            end
        end

        function turnsOffEveryStandaloneRule(testCase)
            % TumorModel computes tumor_volume from all the populations.
            rules = sbioselect(testCase.Model, "Type", "rule", "Name", testCase.STANDALONE_RULE);
            testCase.verifyNumElements(rules, numel(testCase.POPULATIONS));
            testCase.verifyFalse(any([rules.Active]), "Every " + testCase.STANDALONE_RULE + " must be off");
        end

        function verifies(testCase)
            testCase.verifyWarningFree(@() verify(testCase.Model));
        end

        function namesEveryVariantEntryByFullName(testCase)
            % A variant entry that names anything but a resolved quantity,
            % by its full name or its name relative to TumorModel, is
            % silently ignored: for example, one still starting with
            % ADCBystander.
            for variant = testCase.Model.Variants'
                names = variantEntries(variant);
                applies = arrayfun(@(name) appliesTo(testCase.Model, testCase.Resolved, name), names);
                testCase.verifyEmpty(names(~applies), variant.Name + ": not the full name of a resolved quantity");
            end
        end

        function scenarioSetsCellFractionsThatSumToOne(testCase, scenario)
            variant = sbioselect(testCase.Model.Variants, "Name", scenario);
            testCase.verifyEqual(sort(variantEntries(variant)), ...
                sort(testCase.MODEL_NAME + ".cell_fraction_" + testCase.POPULATIONS));
            values = cellfun(@(entry) entry{4}, variant.Content);
            testCase.verifyEqual(sum(values), 1, AbsTol=1e-12);
        end

        function simulatesSpeciesAsAmounts(testCase)
            cs = getconfigset(testCase.Model, "active");
            testCase.verifyEqual(string(cs.CompileOptions.DefaultSpeciesDimension), "substance");
        end

        function givesEveryQuantityUnits(testCase)
            quantities = allQuantities(testCase.Model);
            testCase.verifyEmpty(fullNames(quantities(cellfun(@isempty, {quantities.Units}))), ...
                "These quantities have no units");
        end

        % --- behavior ---------------------------------------------------
        function seedsEachPopulationFromItsCellFraction(testCase, scenario)
            c = testCase.columnsFor(scenario);
            for p = testCase.POPULATIONS
                testCase.verifyEqual(c.("Tumor_total_cell_" + p)(1), c.("cell_fraction_" + p)(1) ...
                    *c.total_cell_volume_tumor_init(1)/c.volume_per_cell(1), AbsTol=1, RelTol=1e-12);
            end
        end

        function computesTumorVolumeFromAllPopulations(testCase, scenario)
            c = testCase.columnsFor(scenario);
            cells = 0;
            for p = testCase.POPULATIONS
                cells = cells + c.("Tumor_total_cell_" + p);
            end
            testCase.verifyEqual(c.tumor_volume, (cells + c.MOL_UNIT).*c.volume_per_cell./(1 - c.epsilon_payload), ...
                RelTol=1e-9);
        end

        function losesADCOnlyByDegradation(testCase, scenario)
            % Binding, internalization and cell death only move ADC.
            c = testCase.columnsFor(scenario);
            total = c.Tumor_A;
            for p = testCase.AG_POSITIVE
                b = p + "_Binding_Tumor_";
                total = total + c.(b + "AT_" + p) + c.(b + "ATT_" + p) + c.(b + "A_int_" + p) + c.(b + "Degraded");
            end
            testCase.verifyEqual(total, repmat(total(1), size(total)), RelTol=testCase.TOLERANCE);
        end

        function releasesPayloadOnlyFromDegradedADC(testCase, scenario)
            % Average_DAR payloads per degraded ADC; the cells only move
            % payload between the tumor and themselves.
            c = testCase.columnsFor(scenario);
            payload = c.Tumor_P;
            released = 0;
            for p = testCase.POPULATIONS
                payload = payload + c.(p + "_CellDyn_Tumor_P_int_" + p);
            end
            for p = testCase.AG_POSITIVE
                b = p + "_Binding_";
                released = released + c.(b + "Average_DAR")(1)/c.(b + "MOL_UNIT")(1)*c.(b + "Tumor_Degraded");
            end
            testCase.verifyEqual(payload - payload(1), released, AbsTol=testCase.TOLERANCE*max(abs(payload)));
        end

        function killsEveryPopulationPresent(testCase, scenario)
            % Ag+ cells by the ADC they bind, Ag- cells by the payload the
            % Ag+ cells release (bystander killing); a population that is
            % not seeded stays empty.
            c = testCase.columnsFor(scenario);
            for p = testCase.POPULATIONS
                cells = c.("Tumor_total_cell_" + p);
                if cells(1) > 0
                    testCase.verifyLessThan(cells(end), cells(1), p + " must be killed");
                else
                    testCase.verifyEqual(cells, zeros(size(cells)), p + " must stay empty");
                end
            end
        end
    end

    methods (Access = private)
        function c = columnsFor(testCase, scenario)
            % The scenario's run, if its variant applies: SimBiology ignores
            % an entry that does not, so the run would not be the scenario.
            unapplied = testCase.Unapplied.(matlab.lang.makeValidName(scenario));
            testCase.assumeEmpty(unapplied, scenario + " does not apply: its entries " + ...
                strjoin(unapplied, ", ") + " are not names in TumorModel. Remove the ADCBystander. prefix.");
            c = testCase.Runs.(matlab.lang.makeValidName(scenario));
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

function quantities = allQuantities(model)
quantities = [sbioselect(model, "Type", "compartment"); sbioselect(model, "Type", "species")
    sbioselect(model, "Type", "parameter")];
end

function names = fullNames(components)
names = string(get(components, {"FullyQualifiedName"}))';
end

function resolved = resolvedNames(model)
% A dictionary from the full name of each quantity in one of the sets that
% apply with model as the current model, to the full name of the set's
% resolved quantity.
resolved = dictionary(string.empty, string.empty);
for set = model.EquivalenceSets'
    if set.ModelScope == model
        for q = set.Quantities'
            resolved(string(q.FullyQualifiedName)) = string(set.ResolvedQuantity.FullyQualifiedName);
        end
    end
end
end

function name = resolvedName(resolved, fullName)
name = string(fullName);
if isKey(resolved, name)
    name = resolved(name);
end
end

function members = membersOf(model, resolved, fullName)
% The full names of the members of the set that contains fullName.
target = resolvedName(resolved, fullName);
members = keys(resolved);
members = members(values(resolved) == target)';
if isempty(members)
    members = string(fullName);
end
end

function names = variantEntries(variant)
names = string(cellfun(@(entry) entry{2}, variant.Content, "UniformOutput", false))';
end

function tf = appliesTo(model, resolved, name)
% Whether a variant entry naming name sets a quantity of model, when model
% is simulated on its own: name is a full name, or a name relative to model.
if ~startsWith(name, model.Name + ".")
    name = model.Name + "." + name;
end
quantity = sbioselect(model, "FullyQualifiedName", name);
tf = isscalar(quantity) && resolvedName(resolved, name) == name;
end

% -------------------------------------------------------------------------
% Simulation

function model = accountingCopy(source, agPositive)
% A copy to simulate on an hourly grid, in which intracellular degradation
% in each Binding makes its Tumor.Degraded, so ADC and payload can be
% accounted for. Products do not change the rates, which are written out.
% The saved model is left as it is.
model = copyobj(source);
for p = agPositive
    binding = sbioselect(model, "Type", "sbiomodel", "Where", "FullyQualifiedName", "==", ...
        model.Name + "." + p + ".Binding");
    tumor = sbioselect(binding.Compartments, "Name", "Tumor");
    degraded = addspecies(tumor, "Degraded", 0, "Units", "nanomole");
    addproduct(sbioselect(binding.Reactions, "Name", "Intracellular ADC degradation"), degraded);
end
cs = getconfigset(model, "active");
cs.SolverOptions.OutputTimes = 0:1:cs.StopTime;
cs.MaximumWallClock = 120;  % seconds: stop, rather than hang, if it is too stiff to run
end

function columns = simulate(model, variants)
% Every quantity, as a struct of columns named by full name relative to
% model, with dots as underscores; a connected quantity's column is the
% data of the quantity that stands in for it. Also time.
cs = getconfigset(model, "active");
resolved = resolvedNames(model);
quantities = allQuantities(model);
stands = arrayfun(@(q) resolvedName(resolved, q.FullyQualifiedName), quantities);
cs.RuntimeOptions.StatesToLog = quantities(stands == fullNames(quantities)');
res = sbiosimulate(model, cs, variants);
columns = struct("time", res.Time);
for k = 1:numel(quantities)
    [~, data] = selectbyname(res, stands(k));
    columns.(replace(erase(string(quantities(k).FullyQualifiedName), model.Name + "."), ".", "_")) = data;
end
end
