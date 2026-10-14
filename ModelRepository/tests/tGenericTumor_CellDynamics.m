classdef tGenericTumor_CellDynamics < matlab.unittest.TestCase
    %tGenericTumor_CellDynamics  What GenericCellDynamics guarantees to anyone who uses it.
    %
    %   GenericCellDynamics, in GenericTumorCellModels.sbproj, is one
    %   population of cells in a tumor. The cells grow, either on their own
    %   (k_self_doubling_for_subtype) or recruited by other cells
    %   (k_recruited_doubling_for_subtype). Free payload in the tumor,
    %   Tumor.P, crosses into the cells, and internalized payload,
    %   Tumor.P_int_subtype, kills them through three transit stages. Dying
    %   cells release their payload back into the tumor.
    %
    %   Why test a model? Models in the repository are built to be reused,
    %   by people who did not build them. This test is the model's
    %   contract: each test is one thing the model guarantees, and no
    %   version of the model goes into the repository unless it passes. If
    %   you import GenericCellDynamics, you can rely on what is tested
    %   here. If you change it, run the test: a failure means you broke
    %   something someone else may depend on.
    %
    %   Each test is named for its guarantee, so the list of results reads
    %   as the model's specification. There are two kinds:
    %
    %   - Structure: what is in the model. The quantities a parent model
    %     connects to, and the naming that tells you how: quantities every
    %     population shares can be matched by name, quantities specific to
    %     one population end in "subtype" and must be matched another way
    %     (by renaming them for the population with parameterizeSubmodels),
    %     and every other parameter is internal to the model and tagged
    %     "local". What a parent model supplies is tagged "placeholder".
    %     The TumorCell and StromaCell
    %     variants choose the growth mode, and the standalone driver
    %     supplies what a parent model would.
    %   - Behavior: what the model does. Run on its own, under the driver,
    %     in each growth mode: the population starts at the size the
    %     initial tumor volume implies, cells appear only by growth and
    %     disappear only by removal, payload is never created or destroyed,
    %     and without payload the population grows as its growth mode
    %     predicts.
    %
    %   runtests("ModelRepository/tests/tGenericTumor_CellDynamics.m")
    %
    %   ShowPlots is true by default, so each run also plots the population
    %   size and growth rate for both growth modes. Set it to false to run
    %   without figures:
    %       tc = tGenericTumor_CellDynamics; tc.ShowPlots = false; run(tc);
    %
    % Without payload nothing dies, so the population grows at
    %   d(cells)/dt = k_self*cells + k_recruited*recruiting:
    % exponentially for TumorCell (k_recruited = 0) and linearly for
    % StromaCell (k_self = 0, recruiting held by the driver).

    properties
        % When true (the default), plot the population size and growth rate
        % for each growth mode. Set false to run without figures.
        ShowPlots (1,1) logical = true
    end

    properties (Constant)
        MODEL_PROJECT = fullfile(fileparts(fileparts(mfilename("fullpath"))), "GenericTumorCellModels.sbproj")
        MODEL_NAME = "GenericCellDynamics"
        DRIVER = "Drivers for testing standalone model"
        STANDALONE_RULE = "Rule_tumor_volume_standalone"
        SUBTYPE = "subtype"
        LOCAL_TAG = "local"
        PLACEHOLDER_TAG = "placeholder"
        % What every cell population in a tumor shares, so a parent model
        % can connect them all by name.
        SHARED_BY_ALL_POPULATIONS = ["Tumor" "Tumor.P" "tumor_volume" "total_cell_volume_tumor_init" ...
            "volume_per_cell" "epsilon_payload" "cell_radius" "MOL_UNIT"]
        % What is specific to this population: a parent model with several
        % populations connects each one to its own placeholder.
        POPULATION_SPECIFIC = ["Tumor.live_cell_subtype" "Tumor.total_cell_subtype" "Tumor.P_int_subtype" ...
            "Tumor.total_recruiting_cell_for_subtype" "growth_rate_subtype" "death_rate_subtype" ...
            "cell_fraction_subtype" "k_self_doubling_for_subtype" "k_recruited_doubling_for_subtype"]
        % What the driver supplies in place of a parent model.
        DRIVEN = ["Tumor.P" "Tumor.total_recruiting_cell_for_subtype"]
        % What a parent model supplies: what the driver sets, and what the
        % standalone rule sets.
        PLACEHOLDERS = ["Tumor.P" "Tumor.total_recruiting_cell_for_subtype" "tumor_volume"]
        GROWTH_CONSTANTS = ["k_self_doubling_for_subtype" "k_recruited_doubling_for_subtype"]
        TOLERANCE = 1e-6        % relative
        % Population size at the peak and at the end of the week under the
        % driver, as recorded by the model's author.
        CELL_COUNT_TOLERANCE = 0.01
        EXPECTED_CELLS = struct( ...
            "TumorCell",  struct("Peak", 5.16e8, "Final", 2.43e8), ...
            "StromaCell", struct("Peak", 5.17e8, "Final", 3.33e8))
    end

    properties (TestParameter)
        growthMode = {"TumorCell", "StromaCell"}
        quantity = {"Tumor", "Tumor.P", "tumor_volume", "total_cell_volume_tumor_init", ...
            "volume_per_cell", "epsilon_payload", "cell_radius", "MOL_UNIT", ...
            "Tumor.live_cell_subtype", "Tumor.total_cell_subtype", "Tumor.P_int_subtype", ...
            "Tumor.total_recruiting_cell_for_subtype", "growth_rate_subtype", "death_rate_subtype", ...
            "cell_fraction_subtype", "k_self_doubling_for_subtype", "k_recruited_doubling_for_subtype"}
    end

    properties (Access = private)
        Model       % GenericCellDynamics, as saved
        Driver      % its standalone driver
        Runs        % struct, per growth mode, of logged columns under the driver
        NoPayload   % the same, with no payload in the tumor
    end

    methods (TestClassSetup)
        function loadAndSimulate(testCase)
            project = sbioloadproject(testCase.MODEL_PROJECT);
            testCase.Model = modelNamed(project, testCase.MODEL_NAME);
            testCase.Driver = sbioselect(testCase.Model.Variants, "Name", testCase.DRIVER);
            testCase.assertNumElements(testCase.Driver, 1, "The model must have one variant named " + testCase.DRIVER);
            model = accountingCopy(testCase.Model);
            noPayload = sbiovariant("no payload");
            addcontent(noPayload, {"species", "Tumor.P", "Value", 0});
            for mode = string(testCase.growthMode)
                growth = sbioselect(model.Variants, "Name", mode);
                testCase.assertNumElements(growth, 1, "The model must have one variant named " + mode);
                testCase.Runs.(mode) = simulate(model, [testCase.Driver, growth]);
                testCase.NoPayload.(mode) = simulate(model, [testCase.Driver, growth, noPayload]);
            end
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
            % The driver and the standalone rule stand in for these; a
            % parent model must connect them.
            quantities = ownQuantities(testCase.Model);
            names = relativeNames(testCase.Model, quantities);
            isPlaceholder = arrayfun(@(q) any(string(q.Tags) == testCase.PLACEHOLDER_TAG), quantities)';
            testCase.verifyEqual(sort(names(isPlaceholder)), sort(testCase.PLACEHOLDERS));
        end

        function computesTumorVolumeWhenStandalone(testCase)
            % Its standalone rule computes tumor_volume from this population
            % alone. It ships active, so the model simulates on its own;
            % turn it off when a parent model computes tumor_volume.
            rule = sbioselect(testCase.Model.Rules, "Name", testCase.STANDALONE_RULE);
            testCase.assertNumElements(rule, 1, "The model has no rule named " + testCase.STANDALONE_RULE);
            testCase.verifyTrue(rule.Active, testCase.STANDALONE_RULE + " must ship active");
            testCase.verifyEqual(strtrim(extractBefore(string(rule.Rule), "=")), "tumor_volume");
        end

        function growthModeVariantSetsOnlyGrowthConstants(testCase, growthMode)
            % Apply TumorCell or StromaCell, or commit it, to choose how the
            % population grows, without changing anything else.
            variant = sbioselect(testCase.Model.Variants, "Name", growthMode);
            testCase.verifyEqual(sort(drivenNames(variant, testCase.Model)), sort(testCase.GROWTH_CONSTANTS));
        end

        function driverSuppliesPayloadAndRecruitingCells(testCase)
            % Apply it to run the model on its own: it supplies what a
            % parent model would.
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
        function seedsPopulationFromInitialTumorVolume(testCase, growthMode)
            % cell_fraction_subtype of the initial tumor volume, in cells.
            start = initial(testCase.Runs.(growthMode));
            testCase.verifyEqual(start.Tumor_total_cell_subtype, ...
                start.cell_fraction_subtype*start.total_cell_volume_tumor_init/start.volume_per_cell, ...
                RelTol=1e-12);
        end

        function changesCellsOnlyByGrowthAndRemoval(testCase, growthMode)
            % Cells pass through the death stages, but are only created by
            % growth and only lost when dead cells are removed.
            columns = testCase.Runs.(growthMode);
            balance = columns.Tumor_total_cell_subtype - columns.Tumor_Grown + columns.Tumor_Removed;
            testCase.verifyEqual(balance, repmat(balance(1), size(balance)), RelTol=testCase.TOLERANCE);
        end

        function neverCreatesOrDestroysPayload(testCase, growthMode)
            % Payload only moves between the tumor and the cells.
            columns = testCase.Runs.(growthMode);
            total = columns.Tumor_P + columns.Tumor_P_int_subtype;
            testCase.verifyEqual(total, repmat(total(1), size(total)), RelTol=testCase.TOLERANCE);
        end

        function computesGrowthRateFromGrowthMode(testCase, growthMode)
            % growth_rate_subtype, which a parent model can read, is the
            % rate at which this population grows.
            c = testCase.Runs.(growthMode);
            testCase.verifyEqual(c.growth_rate_subtype, ...
                c.k_self_doubling_for_subtype.*c.Tumor_live_cell_subtype ...
                + c.k_recruited_doubling_for_subtype.*c.Tumor_total_recruiting_cell_for_subtype, ...
                RelTol=testCase.TOLERANCE);
            testCase.plotResults(c, growthMode);
        end

        function tumorCellGrowsExponentiallyWithoutPayload(testCase)
            c = testCase.NoPayload.TumorCell;
            testCase.verifyEqual(c.Tumor_total_cell_subtype, ...
                c.Tumor_total_cell_subtype(1)*exp(c.k_self_doubling_for_subtype(1)*c.time), ...
                RelTol=testCase.TOLERANCE);
        end

        function stromaCellGrowsLinearlyWithoutPayload(testCase)
            % At the rate the recruiting cells set.
            c = testCase.NoPayload.StromaCell;
            testCase.verifyEqual(c.Tumor_total_cell_subtype, c.Tumor_total_cell_subtype(1) ...
                + c.k_recruited_doubling_for_subtype(1)*c.Tumor_total_recruiting_cell_for_subtype(1)*c.time, ...
                RelTol=testCase.TOLERANCE);
        end

        function payloadKillsPopulationWithinAWeek(testCase, growthMode)
            % Under the driver's payload, the population peaks early, then
            % is driven down: further for TumorCell, whose growth falls as
            % its own cells die, than for StromaCell, whose recruitment
            % stays constant.
            cells = testCase.Runs.(growthMode).Tumor_total_cell_subtype;
            expected = testCase.EXPECTED_CELLS.(growthMode);
            testCase.verifyEqual(max(cells), expected.Peak, RelTol=testCase.CELL_COUNT_TOLERANCE);
            testCase.verifyEqual(cells(end), expected.Final, RelTol=testCase.CELL_COUNT_TOLERANCE);
        end
    end

    methods (Access = private)
        function plotResults(testCase, columns, titleText)
            if ~testCase.ShowPlots
                return
            end
            figure("Name", "GenericCellDynamics - " + titleText);
            subplot(2, 1, 1);
            plot(columns.time, columns.Tumor_total_cell_subtype);
            ylabel("total\_cell\_subtype (molecule)");
            title(titleText);
            grid on;
            subplot(2, 1, 2);
            plot(columns.time, columns.growth_rate_subtype);
            xlabel("time (hour)");
            ylabel("growth\_rate\_subtype (molecule/hour)");
            grid on;
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
% The quantities a variant sets, named relative to model; errors on an
% entry naming nothing, which SimBiology would silently ignore.
names = strings(1, numel(variant.Content));
for k = 1:numel(variant.Content)
    entry = variant.Content{k};
    names(k) = entry{2};
    assert(isscalar(sbioselect(model, "Type", entry{1}, "FullyQualifiedName", ...
        model.FullyQualifiedName + "." + names(k))), ...
        "tGenericTumor_CellDynamics:content", "%s names %s, not in %s", variant.Name, names(k), model.Name);
end
end

% -------------------------------------------------------------------------
% Simulation

function model = accountingCopy(source)
% A copy to simulate on an hourly grid at tight tolerances, in which growth
% makes Tumor.Grown and removal makes Tumor.Removed, so cells can be
% accounted for. Products do not change the rates, which are written out.
% The saved model is left as it is.
model = copyobj(source);
tumor = sbioselect(model.Compartments, "Name", "Tumor");
grown = addspecies(tumor, "Grown", 0, "Units", "molecule");
removed = addspecies(tumor, "Removed", 0, "Units", "molecule");
addproduct(sbioselect(model.Reactions, "Name", "Cell growth - independent"), grown);
addproduct(sbioselect(model.Reactions, "Name", "Cell growth - recruitment"), grown);
addproduct(sbioselect(model.Reactions, "Name", "Damaged cell removal"), removed);
cs = getconfigset(model, "active");
cs.SolverOptions.OutputTimes = 0:1:cs.StopTime;
cs.SolverOptions.RelativeTolerance = 1e-10;
cs.SolverOptions.AbsoluteTolerance = 1e-12;
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
