classdef (Abstract) CellPopulationContract < matlab.unittest.TestCase
    %CellPopulationContract  What every cell population in CellPopulations.sbproj
    %                        guarantees to anyone who uses it.
    %
    %   CellPopulations.sbproj holds one model for each kind of cell in a
    %   tumor: AgPosTumor, AgNegTumor, AgPosStroma and AgNegStroma. Each is
    %   built from the repository's generic models. Its CellDyn submodel is
    %   GenericCellDynamics, and a population that expresses the target
    %   (Ag+) also has a Binding submodel, GenericBinding, connected to
    %   CellDyn through equivalence sets. Each copy is parameterized for its
    %   population: every name that ended in _subtype ends in the
    %   population's name instead (parameterizeSubmodels).
    %
    %   Why test a model? Models in the repository are built to be reused,
    %   by people who did not build them. This test is the model's
    %   contract: each test is one thing the population guarantees, and no
    %   version of it goes into the repository unless it passes. If you
    %   import a population, you can rely on what is tested here. If you
    %   change one, run its test: a failure means you broke something
    %   someone else may depend on.
    %
    %   This class holds the tests; tCellPopulations_<population> runs them
    %   for one population. Each test is named for its guarantee, so the
    %   list of results reads as the model's specification. There are two
    %   kinds:
    %
    %   - Structure: how the population is put together. Which submodels it
    %     is made of, and that they are the repository's generic models,
    %     unchanged except for their parameterized names. In an Ag+
    %     population, every quantity Binding shares with CellDyn is
    %     connected, and resolved in CellDyn. The quantities a tumor model
    %     aggregates across populations are named for this population, so
    %     a tumor model connects them by name to its placeholders. Quantities tagged "local" are not connected to
    %     anything. The population keeps its standalone tumor-volume rule
    %     active, and its variants name what they set by full name, so they
    %     apply.
    %   - Behavior: what the population does on its own. It starts at the
    %     size the initial tumor volume implies, and payload is never
    %     created or destroyed except as ADC releases it. An Ag+ population
    %     is killed by ADC; an Ag- population, which does not bind ADC, is
    %     killed by free payload (bystander killing).

    properties (Abstract, Constant)
        POPULATION      % name of the population model this test is for
    end

    properties (Constant)
        MODEL_PROJECT = fullfile(fileparts(fileparts(mfilename("fullpath"))), "CellPopulations.sbproj")
        GENERIC_PROJECT = fullfile(fileparts(fileparts(mfilename("fullpath"))), "GenericTumorCellModels.sbproj")
        % Each submodel, and the generic model it is a copy of.
        GENERIC = struct("CellDyn", "GenericCellDynamics", "Binding", "GenericBinding")
        SUFFIX = "subtype"      % what parameterizing replaces with the population's name
        LOCAL_TAG = "local"
        STANDALONE_RULE = "Rule_tumor_volume_standalone"
        % Free payload for an Ag- population run on its own: the value
        % GenericCellDynamics's driver uses.
        BYSTANDER_PAYLOAD = 10
        SPECIES_DIMENSION = "substance"
        % Tags that named the tumor-model rate supplying a population's
        % growth; ignored when comparing with the generic models until they
        % are removed from the models.
        GROWTH_TAGS = ["k_self_doubling_tumor" "k_recruited_doubling_stroma" "recruiting_cell_stroma"]
        TOLERANCE = 1e-6        % relative
    end

    properties (Access = private)
        Model       % the population, as saved
        Generic     % struct of the generic models, as saved
        Run         % struct of logged columns: the population on its own
    end

    methods (TestClassSetup)
        function loadAndSimulate(testCase)
            project = sbioloadproject(testCase.MODEL_PROJECT);
            generic = sbioloadproject(testCase.GENERIC_PROJECT);
            for name = string(fieldnames(testCase.GENERIC))'
                testCase.Generic.(name) = modelNamed(generic, testCase.GENERIC.(name));
            end
            testCase.Model = modelNamed(project, testCase.POPULATION);
            model = accountingCopy(testCase.Model);
            variants = model.Variants';
            if ~testCase.isAgPositive()
                variants = [variants, speciesSetting(model, "CellDyn.Tumor.P", testCase.BYSTANDER_PAYLOAD)];
            end
            testCase.Run = simulate(model, variants);
            stopTime = getconfigset(model, "active").StopTime;
            testCase.assertEqual(testCase.Run.time(end), stopTime, ...
                "The simulation stopped before StopTime: the model is too stiff to run in time");
        end
    end

    methods (Test)
        % --- structure --------------------------------------------------
        function isBuiltFromCellDynamicsAndBindingIfAgPositive(testCase)
            expected = "CellDyn";
            if testCase.isAgPositive()
                expected = ["Binding" "CellDyn"];
            end
            testCase.verifyEqual(sort(string({testCase.Model.Models.Name})), expected);
        end

        function copiesGenericModelsUnchangedButForNames(testCase)
            % CellDyn is GenericCellDynamics, and Binding GenericBinding,
            % with _subtype replaced by the population's name: the same
            % reactions, rules, parameter values and tags, so what their
            % tests guarantee holds here too. Only the growth tags, which
            % say which tumor-model rate supplies the population, differ.
            for sub = testCase.Model.Models'
                generic = testCase.Generic.(sub.Name);
                rename = @(text) regexprep(text, "_" + testCase.SUFFIX + "\>", "_" + testCase.POPULATION);
                label = testCase.POPULATION + "." + sub.Name;
                testCase.verifyEqual(reactionsOf(sub), rename(reactionsOf(generic)), label + " reactions");
                testCase.verifyEqual(rulesOf(sub), rename(rulesOf(generic)), label + " rules");
                testCase.verifyEqual(quantitiesOf(sub, testCase.GROWTH_TAGS), ...
                    renameQuantities(quantitiesOf(generic, testCase.GROWTH_TAGS), rename), label + " quantities");
            end
        end

        function namesNothingSubtype(testCase)
            % Every copied name is specific to this population.
            names = componentNames([allQuantities(testCase.Model); sbioselect(testCase.Model, "Type", "rule")
                sbioselect(testCase.Model, "Type", "reaction")]);
            testCase.verifyEmpty(names(endsWith(names, "_" + testCase.SUFFIX)), ...
                "These names were not parameterized");
        end

        function connectsBindingToCellDynamicsByName(testCase)
            % Every quantity Binding shares by name with CellDyn is the
            % same quantity, and CellDyn's is the one that stands in for it.
            % (An Ag- population has no Binding.)
            resolved = resolvedNames(testCase.Model);
            cellDyn = submodel(testCase.Model, "CellDyn");
            binding = submodel(testCase.Model, "Binding");
            if isempty(binding)
                return
            end
            for q = allQuantities(binding)'
                twin = sbioselect(cellDyn, "FullyQualifiedName", replace(q.FullyQualifiedName, ".Binding.", ".CellDyn."));
                if ~isempty(twin)
                    testCase.verifyEqual(resolvedName(resolved, q), string(twin.FullyQualifiedName), ...
                        string(q.FullyQualifiedName) + " must be connected to, and resolved in, CellDyn");
                end
            end
        end

        function namesQuantitiesATumorModelAggregatesForThePopulation(testCase)
            % A tumor model connects each by name to its placeholder for
            % this population, such as total_cell_AgPosTumor.
            for name = testCase.aggregatedQuantities()
                testCase.verifyNumElements(sbioselect(testCase.Model, "FullyQualifiedName", ...
                    testCase.POPULATION + "." + name), 1, name + " is not in " + testCase.POPULATION);
            end
        end

        function connectsNothingTaggedLocal(testCase)
            % A quantity tagged local is internal to its submodel.
            resolved = resolvedNames(testCase.Model);
            quantities = allQuantities(testCase.Model);
            local = quantities(arrayfun(@(q) any(string(q.Tags) == testCase.LOCAL_TAG), quantities));
            testCase.assertNotEmpty(local);
            connected = local(arrayfun(@(q) isKey(resolved, string(q.FullyQualifiedName)), local));
            testCase.verifyEmpty(fullNames(connected), "Tagged " + testCase.LOCAL_TAG + ", but connected");
        end

        function simulatesOnItsOwnUntilAssembled(testCase)
            % CellDyn's standalone rule computes tumor_volume from this
            % population alone. It ships active; turn it off when a tumor
            % model computes tumor_volume from all the populations.
            rule = sbioselect(submodel(testCase.Model, "CellDyn").Rules, "Name", testCase.STANDALONE_RULE);
            testCase.assertNumElements(rule, 1);
            testCase.verifyTrue(rule.Active, testCase.STANDALONE_RULE + " must ship active");
        end

        function namesEveryVariantEntryByFullName(testCase)
            % A population is not flat, so a variant entry must give the
            % full name of the quantity that stands in for the one it
            % sets: an entry naming anything else does not apply.
            resolved = resolvedNames(testCase.Model);
            for variant = testCase.Model.Variants'
                names = variantEntries(variant);
                applies = arrayfun(@(name) appliesTo(testCase.Model, resolved, name), names);
                testCase.verifyEmpty(names(~applies), variant.Name + ": not the full name of a resolved quantity");
            end
        end

        function simulatesSpeciesAsAmounts(testCase)
            % Its species are amounts (molecules and nanomoles), as in a
            % tumor model; simulated as concentrations, the population is
            % too stiff to run.
            cs = getconfigset(testCase.Model, "active");
            testCase.verifyEqual(string(cs.CompileOptions.DefaultSpeciesDimension), testCase.SPECIES_DIMENSION);
        end

        function givesEveryQuantityUnits(testCase)
            % So it can be combined with models in other units.
            quantities = allQuantities(testCase.Model);
            testCase.verifyEmpty(fullNames(quantities(cellfun(@isempty, {quantities.Units}))), ...
                "These quantities have no units");
        end

        % --- behavior ---------------------------------------------------
        function seedsPopulationFromInitialTumorVolume(testCase)
            % cell_fraction_<population> of the initial tumor volume, in cells.
            c = testCase.Run;
            p = testCase.POPULATION;
            testCase.verifyEqual(c.("CellDyn_Tumor_total_cell_" + p)(1), c.("CellDyn_cell_fraction_" + p)(1) ...
                *c.CellDyn_total_cell_volume_tumor_init(1)/c.CellDyn_volume_per_cell(1), RelTol=1e-12);
        end

        function releasesPayloadOnlyFromDegradedADC(testCase)
            % Average_DAR payloads per ADC degraded in the cells of an Ag+
            % population; CellDyn only moves payload between the tumor and
            % the cells, so an Ag- population, which binds no ADC, never
            % creates or destroys payload.
            c = testCase.Run;
            total = c.CellDyn_Tumor_P + c.("CellDyn_Tumor_P_int_" + testCase.POPULATION);
            released = total - total(1);
            expected = zeros(size(released));
            if testCase.isAgPositive()
                expected = c.Binding_Average_DAR(1)/c.Binding_MOL_UNIT(1)*c.Binding_Tumor_Degraded;
            end
            testCase.verifyEqual(released, expected, AbsTol=testCase.TOLERANCE*max(abs(total)));
        end

        function isKilledByADCOrBystanderPayload(testCase)
            % Ag+ cells by the ADC they bind; Ag- cells by free payload
            % that enters them without binding (bystander killing).
            live = testCase.Run.("CellDyn_Tumor_live_cell_" + testCase.POPULATION);
            testCase.verifyLessThan(live(end), live(1));
        end
    end

    methods (Access = private)
        function tf = isAgPositive(testCase)
            tf = startsWith(testCase.POPULATION, "AgPos");
        end

        function names = aggregatedQuantities(testCase)
            % What a tumor model aggregates, relative to the population.
            p = testCase.POPULATION;
            names = ["CellDyn.Tumor.total_cell_" + p, "CellDyn.Tumor.live_cell_" + p, ...
                "CellDyn.Tumor.P_int_" + p, "CellDyn.cell_fraction_" + p];
            if testCase.isAgPositive()
                names = [names, "Binding.Tumor.ADC_bound_" + p];
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

function model = submodel(model, name)
model = model.Models(string({model.Models.Name}) == name);
end

function quantities = allQuantities(model)
% Every compartment, species and parameter, in model and its submodels.
quantities = [sbioselect(model, "Type", "compartment"); sbioselect(model, "Type", "species")
    sbioselect(model, "Type", "parameter")];
end

function names = componentNames(components)
names = string(get(components, {"Name"}))';
end

function names = fullNames(components)
names = string(get(components, {"FullyQualifiedName"}))';
end

function resolved = resolvedNames(model)
% A dictionary from the full name of each quantity in one of model's
% equivalence sets to the full name of the set's resolved quantity.
resolved = dictionary(string.empty, string.empty);
for set = model.EquivalenceSets'
    for q = set.Quantities'
        resolved(string(q.FullyQualifiedName)) = string(set.ResolvedQuantity.FullyQualifiedName);
    end
end
end

function name = resolvedName(resolved, quantity)
% The full name of the quantity that stands in for quantity.
name = string(quantity.FullyQualifiedName);
if isKey(resolved, name)
    name = resolved(name);
end
end

function names = variantEntries(variant)
names = string(cellfun(@(entry) entry{2}, variant.Content, "UniformOutput", false));
end

function tf = appliesTo(model, resolved, name)
% Whether a variant entry naming name sets a quantity of model.
quantity = sbioselect(model, "FullyQualifiedName", name);
tf = isscalar(quantity) && resolvedName(resolved, quantity) == name;
end

function table = reactionsOf(model)
table = sortrows([string({model.Reactions.Name})' string({model.Reactions.Reaction})' ...
    string({model.Reactions.ReactionRate})']);
end

function table = rulesOf(model)
table = sortrows([string({model.Rules.Name})' string({model.Rules.Rule})']);
end

function table = quantitiesOf(model, ignoredTags)
% Rows of [full name relative to model, value, tags], sorted by name,
% leaving out the ignored tags.
quantities = allQuantities(model);
names = erase(fullNames(quantities), model.FullyQualifiedName + ".")';
values = string(arrayfun(@(q) q.Value, quantities));
tags = string(arrayfun(@(q) strjoin(sort(setdiff(string(q.Tags), ignoredTags)), ","), quantities));
table = sortrows([names values tags]);
end

function table = renameQuantities(table, rename)
% A quantity table, with names renamed, sorted by the new names.
table(:, 1) = rename(table(:, 1));
table = sortrows(table);
end

% -------------------------------------------------------------------------
% Simulation

function model = accountingCopy(source)
% A copy to simulate on an hourly grid, at the saved tolerances, in which, for
% an Ag+ population, intracellular degradation makes Binding's
% Tumor.Degraded, so payload can be accounted for. Products do not change
% the rates, which are written out. The saved model is left as it is.
model = copyobj(source);
binding = submodel(model, "Binding");
if ~isempty(binding)
    tumor = sbioselect(binding.Compartments, "Name", "Tumor");
    degraded = addspecies(tumor, "Degraded", 0, "Units", "nanomole");
    addproduct(sbioselect(binding.Reactions, "Name", "Intracellular ADC degradation"), degraded);
end
cs = getconfigset(model, "active");
cs.SolverOptions.OutputTimes = 0:1:cs.StopTime;
cs.MaximumWallClock = 120;  % seconds: stop, rather than hang, if it is too stiff to run
end

function variant = speciesSetting(model, name, value)
% A variant, not in the model, setting the species with full name
% model.name.
variant = sbiovariant("test " + name);
addcontent(variant, {"species", model.Name + "." + name, "Value", value});
end

function columns = simulate(model, variants)
% Every quantity, as a struct of columns named by full name relative to
% model, with dots as underscores; a connected quantity's column is the
% data of the quantity that stands in for it. Also time.
cs = getconfigset(model, "active");
resolved = resolvedNames(model);
quantities = allQuantities(model);
stands = arrayfun(@(q) resolvedName(resolved, q), quantities);
cs.RuntimeOptions.StatesToLog = quantities(stands == fullNames(quantities)');
res = sbiosimulate(model, cs, variants);
columns = struct("time", res.Time);
for k = 1:numel(quantities)
    [~, data] = selectbyname(res, stands(k));
    columns.(replace(erase(string(quantities(k).FullyQualifiedName), model.Name + "."), ".", "_")) = data;
end
end
