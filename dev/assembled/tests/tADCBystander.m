classdef tADCBystander < matlab.unittest.TestCase
    % tADCBystander  Locks the assembled ADC Bystander model to an Excel baseline.
    %
    %   Regression test for the fully integrated hierarchical model
    %   (ADCBystander = SystemicPK + TumorModel + cell populations). For each of
    %   the paper's three cell-population cases it applies the matching scenario
    %   variant and a single dose, simulates, resamples the SimData onto the
    %   baseline time grid, and compares a curated set of fully-qualified states
    %   against expected values stored in an Excel workbook.
    %
    %   Baseline layout (referenceADCBystanderResults.xlsx): one sheet per case,
    %   each sheet named after the case's variant truncated to Excel's 31-char
    %   sheet-name limit. Row 1 holds the column headers -- a "Time" column
    %   (hours) followed by one fully-qualified state name (FQN) per logged
    %   state. Each data row is the expected value of every state at that time.
    %   The FQNs in the header are exactly the names passed to selectbyname, so
    %   the comparison set is driven entirely by the spreadsheet -- add or remove
    %   a state by editing the workbook, not this file.
    %
    %   Prerequisites (paths relative to the repository root):
    %     - dev/assembled/ADCBystander_Assembled.sbproj   the assembled model
    %     - data/referenceADCBystanderResults.xlsx         the expected-value workbook
    %
    %   Run all cases:
    %       runtests("tADCBystander")
    %
    %   ShowPlots is true by default: each case also plots expected vs. simulated
    %   trajectories for every compared state, so a failure is easy to read. Run
    %   without figures with:
    %       tc = tADCBystander; tc.ShowPlots = false; run(tc);

    properties (Constant)
        % --- inputs (all resolved relative to this file's folder) ---
        ProjectFile   = fullfile("..", "ADCBystander_Assembled.sbproj")
        RootModelName = "ADCBystander"                     % top-level model in the project
        ReferenceFile = fullfile("..", "..", "..", "data", "referenceADCBystanderResults.xlsx")

        % SystemicPK defines one repeat dose whose default (dose_repeat = 0)
        % is a single administration, matching the single-dose baseline.
        DoseModelName = "SystemicPK"
        DoseName = 'IV_dose';

        TimeColumn          = "Time"      % baseline time-column header (hours)
        InterpolationMethod = "pchip"     % SimData.resample method onto the baseline grid
        MaxSheetNameLength  = 31          % Excel sheet-name limit; sheets are variant names truncated to this

        % --- simulation setup (match how the baseline was generated) ---
        SimulationStopTime      = 504     % hours
        SolverAbsoluteTolerance = 1e-10
        SolverRelativeTolerance = 1e-08

        % --- comparison tolerances (verifyEqual passes within RelTol OR AbsTol;
        % AbsTol covers the columns that are identically zero for a case) ---
        CompareRelativeTolerance = 1e-3
        CompareAbsoluteTolerance = 1e-6
    end

    properties
        % When true (the default), plot expected vs. simulated for every compared
        % state, one figure per case. Set false to run without figures.
        ShowPlots (1,1) logical = true
    end

    properties (Access = private)
        Model         % loaded ADCBystander SimBiology.Model (root)
        Configset     % configured "active" configset
        Dose          % dose object applied to every run
    end

    properties (TestParameter)
        % One entry per case. The value is the FULL variant name as owned by the
        % model; the baseline sheet name is this truncated to MaxSheetNameLength.
        Case = struct( ...
            'OneCell',     "One-Cell Type Model", ...
            'Independent', "Independent Growth Bystander Model", ...
            'Recruitment', "Recruitment Bystander Model")
    end

    methods (TestClassSetup)
        function loadModel(testCase)
            % Load the assembled root model and configure it to match the baseline run.
            here = fileparts(mfilename("fullpath"));
            projectFile = fullfile(here, testCase.ProjectFile);
            testCase.assertTrue(isfile(projectFile), ...
                "Expected the assembled project in dev/assembled: " + projectFile);

            m = loadModelByName(projectFile, testCase.RootModelName);

            cs = getconfigset(m, "active");
            cs.StopTime = testCase.SimulationStopTime;
            cs.SolverOptions.AbsoluteTolerance = testCase.SolverAbsoluteTolerance;
            cs.SolverOptions.RelativeTolerance = testCase.SolverRelativeTolerance;
            cs.RuntimeOptions.StatesToLog = "all";   % log every submodel state so any FQN is available

            testCase.Model = m;
            testCase.Configset = cs;
        end

        function loadDose(testCase)
            % Select the dose by name; its default schedule is one administration,
            % matching the baseline.
            doseModel = findobj(testCase.Model.Models, "-depth", 0, "Name", testCase.DoseModelName);
            testCase.Dose = getdose(doseModel, testCase.DoseName);
            testCase.assertNumElements(testCase.Dose, 1, "Dose " + testCase.DoseName + " not found");
        end

        function checkReferenceFile(testCase)
            here = fileparts(mfilename("fullpath"));
            refFile = fullfile(here, testCase.ReferenceFile);
            testCase.assertTrue(isfile(refFile), ...
                "Expected the baseline workbook in data: " + refFile);
        end
    end

    methods (Test)
        function matchesBaseline(testCase, Case)
            % Arrange: pull this case's expected values and its scenario variant.
            baseline = testCase.readBaseline(Case);
            variant  = testCase.variantByName(Case);

            % Act: simulate with the scenario variant + dose, then resample onto
            % the baseline time grid.
            resampled = testCase.simulateOnGrid(variant, baseline.Time);

            % Assert: every state in the baseline matches (and, if enabled, plot).
            testCase.verifyAllStates(resampled, baseline, Case);
        end
    end

    methods (Access = private)
        function baseline = readBaseline(testCase, variantName)
            % Read the sheet for this case into a struct with a Time vector and a
            % States table whose variable names are the state FQNs. The sheet is
            % the variant name truncated to Excel's 31-char limit.
            here    = fileparts(mfilename("fullpath"));
            refFile = fullfile(here, testCase.ReferenceFile);
            sheet   = truncate(variantName, testCase.MaxSheetNameLength);

            availableSheets = string(sheetnames(refFile));
            testCase.assertTrue(any(availableSheets == sheet), ...
                "Baseline workbook has no sheet """ + sheet + """ for variant """ + ...
                variantName + """. Sheets present: " + strjoin(availableSheets, ", "));

            % Preserve the original (dotted) FQN headers as table variable names.
            tbl = readtable(refFile, "Sheet", sheet, "VariableNamingRule", "preserve");

            variableNames = string(tbl.Properties.VariableNames);
            testCase.assertTrue(any(variableNames == testCase.TimeColumn), ...
                "Sheet """ + sheet + """ has no """ + testCase.TimeColumn + """ column.");

            baseline.Time       = tbl.(testCase.TimeColumn);
            baseline.StateNames = variableNames(variableNames ~= testCase.TimeColumn);
            baseline.Table      = tbl;
            baseline.Variant    = variantName;
        end

        function variant = variantByName(testCase, variantName)
            % The scenario variants live on the TumorModel submodel; sbioselect
            % recurses the whole hierarchy to find them.
            variant = sbioselect(testCase.Model, "Type", "variant", "Name", variantName);
            testCase.assertNumElements(variant, 1, ...
                "Expected exactly one variant named """ + variantName + """.");
        end

        function resampled = simulateOnGrid(testCase, variant, referenceTime)
            % Simulate with the scenario variant and the dose, then resample onto
            % the baseline times. A single IV bolus produces two rows at its dose
            % time (pre-dose IC and post-dose bolus); resample collapses such
            % duplicate-time rows to the last (post-dose) occurrence, so compare
            % on the deduplicated grid via unique(..., "last").
            sd = sbiosimulate(testCase.Model, testCase.Configset, variant, testCase.Dose);

            compareTime = unique(referenceTime, "last");
            testCase.assertGreaterThanOrEqual(sd.Time(end), compareTime(end), ...
                "Simulation ended before the baseline horizon (likely an integration " + ...
                "failure). Check the model before comparing.");

            resampled = resample(sd, compareTime, testCase.InterpolationMethod);
        end

        function verifyAllStates(testCase, resampled, baseline, variantName)
            % Compare every baseline state against the resampled simulation and,
            % when ShowPlots is set, plot expected vs. simulated for the case.
            [~, lastRows] = unique(baseline.Time, "last");
            stateNames = baseline.StateNames;

            numTimes  = numel(resampled.Time);
            numStates = numel(stateNames);
            actualAll   = nan(numTimes, numStates);
            expectedAll = nan(numTimes, numStates);

            for ii = 1:numStates
                stateName = stateNames(ii);
                actual    = testCase.selectState(resampled, stateName);
                expected  = baseline.Table.(stateName)(lastRows);

                testCase.verifyEqual(actual, expected, ...
                    "RelTol", testCase.CompareRelativeTolerance, ...
                    "AbsTol", testCase.CompareAbsoluteTolerance, ...
                    "State """ + stateName + """ differs from baseline for case " + variantName);

                actualAll(:, ii)   = actual;
                expectedAll(:, ii) = expected;
            end

            testCase.plotComparison(resampled.Time, expectedAll, actualAll, stateNames, variantName);
        end

        function data = selectState(testCase, sd, stateName)
            % Logged data for the state whose fully-qualified name equals stateName.
            selected = selectbyname(sd, stateName);
            testCase.assertNumElements(selected.DataNames, 1, ...
                "Expected exactly one logged state named """ + stateName + ...
                """; found " + numel(selected.DataNames) + ". Check the FQN in the baseline header.");
            data = selected.Data;
        end

        function plotComparison(testCase, timeVector, expectedAll, actualAll, stateNames, variantName)
            if ~testCase.ShowPlots
                return
            end
            numStates = numel(stateNames);
            numCols   = 2;
            numRows   = ceil(numStates / numCols);

            figure("Name", "ADCBystander baseline vs. simulation - " + variantName);
            for ii = 1:numStates
                subplot(numRows, numCols, ii);
                plot(timeVector, expectedAll(:, ii), "k-", "LineWidth", 1.5, "DisplayName", "baseline");
                hold on;
                plot(timeVector, actualAll(:, ii), "r--", "LineWidth", 1.25, "DisplayName", "simulated");
                hold off;
                title(fqnTitle(stateNames(ii)), "Interpreter", "none", "FontSize", 8);
                xlabel("time (hour)");
                grid on;
                if ii == 1
                    legend("Location", "best");
                end
            end
            sgtitle(variantName, "Interpreter", "none");
        end
    end
end

% ---- Local helper functions -------------------------------------------------

function m = loadModelByName(projectFile, modelName)
    % Return the SimBiology model named modelName from a project file. Projects
    % store their models as separate variables, so load them all and match on
    % Name -- robust to which variable holds which model.
    contents = sbioloadproject(projectFile);
    vars     = struct2cell(contents);
    isModel  = cellfun(@(v) isa(v, "SimBiology.Model"), vars);
    models   = vars(isModel);
    names    = cellfun(@(mdl) string(mdl.Name), models);
    idx      = find(names == modelName, 1);
    assert(~isempty(idx), "Model '%s' not found in project '%s'.", modelName, projectFile);
    m = models{idx};
end

function shortName = truncate(name, maxLength)
    % Truncate a name to maxLength characters (how the baseline sheets are named).
    name = char(name);
    if numel(name) > maxLength
        shortName = string(name(1:maxLength));
    else
        shortName = string(name);
    end
end

function titleLines = fqnTitle(fullyQualifiedName)
    % Two-line subplot title built from the state's fully-qualified name: the
    % owning submodel path on the first line, the quantity on the second. This
    % keeps the three populations' cell-count states distinguishable by showing
    % which submodel (AgPosTumor / AgNegTumor / AgPosStroma) each belongs to.
    parts = split(string(fullyQualifiedName), ".");
    leaf  = parts(end);
    path  = strjoin(parts(1:end-1), ".");
    titleLines = [path; leaf];
end
