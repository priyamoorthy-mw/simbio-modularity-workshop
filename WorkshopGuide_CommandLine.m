%[text] # SimBiology Modularity Workshop: Command-Line Equivalents
%[text] This live script performs the steps of the workshop guide, `WorkshopGuide.md`, at the MATLAB command line instead of in the SimBiology Model Builder and Model Analyzer. Each section matches a section of the guide, so you can read them side by side or run this script on its own.
%[text] Run it from the repository root. It loads the projects in `ModelRepository` and `dev`, builds the same models you build in the apps, and simulates them. It does not change any project in the repository; the only file it writes is the extracted tumor model in Section 4.3, `dev/TumorModel.sbproj`, the same file you save in the guide. So that it never overwrites your work, the script stops at the start if that file already exists; delete or rename it to run the script again.
%[text] Besides SimBiology's own functions, the script uses two small functions in `ModelRepository/tools`:
%[text] - `matchByName` connects same-named quantities, like Auto-match by name in the Model Builder.
%[text] - `parameterizeModel` renames a copied template's quantities for the model it is used in. \
% Update the root to your repo as needed
root = '/MATLAB Drive/simbio-modularity-workshop-dev';
addpath(fullfile(root, "ModelRepository", "tools"));
repository = fullfile(root, "ModelRepository");
extractedProject = fullfile(root, "dev", "TumorModel.sbproj");
assert(~isfile(extractedProject), "%s already exists. The script saves the extracted TumorModel there " + ...
    "in Section 4.3. Delete or rename it to run the script.", extractedProject);
%%
%[text] ## 1.4 Preview of the assembled model
%[text] Load the assembled model and list the models in its hierarchy.
assembledProject = sbioloadproject(fullfile(root, "dev", "assembled", "ADCBystander_Assembled.sbproj"));
assembled = assembledProject.m1;
disp(sbioselect(assembled, "Type", "sbiomodel"))
%[text] Three equivalence sets, one for each type of quantity: the shared `Tumor` compartment, the free payload `Tumor.P`, and `tumor_volume`. Each lists its members and its resolved quantity, the member used in place of all of them during simulation.
disp(getEquivalenceSet(sbioselect(assembled, "Where", "FullyQualifiedName", "==", "ADCBystander.TumorModel.Tumor")))
disp(getEquivalenceSet(sbioselect(assembled, "Where", "FullyQualifiedName", "==", "ADCBystander.TumorModel.Tumor.P")))
disp(getEquivalenceSet(sbioselect(assembled, "Where", "FullyQualifiedName", "==", "ADCBystander.TumorModel.tumor_volume")))
%[text] Simulate a single IV dose for each of the paper's three cell-population scenarios, as Program1 does in the Model Analyzer.
scenarios = ["One-Cell Type Model" "Independent Growth Bystander Model" "Recruitment Bystander Model"];
assembledTumor = sbioselect(assembled.Models, "Name", "TumorModel");
assembledDose = getdose(sbioselect(assembled.Models, "Name", "SystemicPK"), "IV_dose");
figure
tiledlayout(1, numel(scenarios))
for scenario = scenarios
    results = sbiosimulate(assembled, getconfigset(assembled, "active"), ...
        sbioselect(assembledTumor.Variants, "Name", scenario), assembledDose);
    [t, x] = selectbyname(results, "ADCBystander.TumorModel.tumor_volume");
    nexttile
    plot(t, x)
    title(scenario), xlabel("Time (hour)"), ylabel("tumor\_volume (liter)")
end
%%
%[text] ## 2.0 Developing reusable models
%[text] ### 2.1 Open `ModelRepository/GenericTumorCellModels.sbproj` and inspect the models
genericProject = sbioloadproject(fullfile(repository, "GenericTumorCellModels.sbproj"));
genericCellDynamics = sbioselect([genericProject.m1 genericProject.m2], "Name", "GenericCellDynamics", "Depth", 0);
genericBinding = sbioselect([genericProject.m1 genericProject.m2], "Name", "GenericBinding", "Depth", 0);
disp(genericCellDynamics.Reactions)
%[text] The variants configure the model for a tumor or a stroma cell population, and the driver supplies what a parent model would.
disp(genericCellDynamics.Variants)
%[text] Which expressions use `tumor_volume`, as the Usages section of the Property Editor shows:
disp(sbioselect(genericCellDynamics, "Type", "reaction", "Where", "ReactionRate", "regexp", "tumor_volume"))
disp(sbioselect(genericCellDynamics, "Type", "rule", "Where", "Rule", "regexp", "tumor_volume"))
%[text] Tags show what each quantity is for: `local` marks quantities internal to the model, and `placeholder` marks those that a parent model supplies.
disp(sbioselect(genericCellDynamics, "Tags", "local"))
disp(sbioselect(genericCellDynamics, "Tags", "placeholder"))
%[text] ### 2.2 Simulate the generic model with different driver and configuration variants
%[text] **Tumor cells without payload (drug).** Apply the `TumorCell` and driver variants, with the driver's free payload `Tumor.P` set to 0. A variant applied later overrides an earlier one.
tumorCell = sbioselect(genericCellDynamics.Variants, "Name", "TumorCell");
driver = sbioselect(genericCellDynamics.Variants, "Name", "Drivers for testing standalone model");
noPayload = sbiovariant("No payload");
addcontent(noPayload, {"species", "Tumor.P", "Value", 0});
withoutPayload = sbiosimulate(genericCellDynamics, getconfigset(genericCellDynamics, "active"), [tumorCell, driver, noPayload]);
%[text] **Tumor cells with payload.** The driver variant sets `Tumor.P` to 10.
withPayload = sbiosimulate(genericCellDynamics, getconfigset(genericCellDynamics, "active"), [tumorCell, driver]);
%[text] **Stroma cells with payload.** The `StromaCell` variant turns off independent growth and turns on growth recruited by the driver's recruiting cells.
stromaCell = sbioselect(genericCellDynamics.Variants, "Name", "StromaCell");
stroma = sbiosimulate(genericCellDynamics, getconfigset(genericCellDynamics, "active"), [stromaCell, driver]);
figure, hold on
for results = [withoutPayload withPayload stroma]
    [t, x] = selectbyname(results, "Tumor.total_cell_subtype");
    plot(t, x)
end
legend(["Tumor cells without payload" "Tumor cells with payload" "Stroma cells with payload"])
title("GenericCellDynamics"), xlabel("Time (hour)"), ylabel("total\_cell\_subtype (molecule)")
%[text] ### 2.3 Use MATLAB unit tests to lock down the behavior of models intended for reuse
%[text] Every model in the model repository has a test that states what its author guarantees. Run the test for `GenericCellDynamics`:
cellDynamicsResults = runtests(fullfile(repository, "tests", "tGenericTumor_CellDynamics.m"))
%%
%[text] ## 3.0 Composing submodels
%[text] ### 3.1 Create a new project with a parent model, `AgPosTumor`
%[text] Create the parent model, and configure its configset.
agPosTumor = sbiomodel("AgPosTumor");
cs = getconfigset(agPosTumor, "active");
cs.StopTime = 168;
cs.TimeUnits = "hour";
cs.SolverOptions.AbsoluteTolerance = 1e-10;
cs.SolverOptions.RelativeTolerance = 1e-8;
cs.CompileOptions.DefaultSpeciesDimension = "substance";
%[text] ### 3.2 and 3.3 Import the generic models and move them into the parent model
%[text] The generic models were loaded as top-level models in Section 2.1. `move` makes each one a submodel of `AgPosTumor`. Rename them for their role in `AgPosTumor`.
cellDyn = move(genericCellDynamics, agPosTumor);
cellDyn.Name = "CellDyn";
binding = move(genericBinding, agPosTumor);
binding.Name = "Binding";
disp(agPosTumor.Models)
%[text] ### 3.4 Configure the cell dynamics submodel as a tumor cell population
%[text] Commit the `TumorCell` variant, so `CellDyn` grows as a tumor cell population whether or not the variant is active. `Rule_tumor_volume_standalone` stays active, so `AgPosTumor` simulates on its own.
commit(sbioselect(cellDyn.Variants, "Name", "TumorCell"), cellDyn);
disp(sbioselect(cellDyn.Rules, "Name", "Rule_tumor_volume_standalone"))
%[text] ### 3.5 Create the driver variant for `AgPosTumor`
%[text] Free ADC in the tumor is the only input from outside `AgPosTumor`. A variant on a hierarchical model names what it sets by its full name.
agPosDriver = addvariant(agPosTumor, "Drivers for testing standalone model");
addcontent(agPosDriver, {"species", "AgPosTumor.Binding.Tumor.A", "Value", 1});
agPosDriver.Active = true;
%[text] ### 3.6 and 3.7 Simulate the hierarchical parent model
%[text] Simulating a model applies its own active variants, not those of its submodels. The submodels are not connected yet, so the ADC has no effect and the tumor grows unchecked.
cellCount = "AgPosTumor.CellDyn.Tumor.total_cell_subtype";
cs.RuntimeOptions.StatesToLog = cellCount;
unconnected = sbiosimulate(agPosTumor);
%[text] ### 3.8 Match equivalences
%[text] Connect every pair of same-named quantities in `CellDyn` and `Binding`. Each resolved quantity defaults to the first sibling model, `CellDyn`.
matchByName(agPosTumor);
%[text] ### 3.9 Simulate the hierarchical parent model again
%[text] With the submodels connected, the ADC kills the cells.
connected = sbiosimulate(agPosTumor);
figure, hold on
for results = [unconnected connected]
    [t, x] = selectbyname(results, cellCount);
    plot(t, x)
end
legend(["Before matching" "After matching"])
title("AgPosTumor"), xlabel("Time (hour)"), ylabel("total\_cell\_subtype (molecule)")
%[text] ### 3.10 Simulate `CellDyn` in isolation
%[text] A submodel can be simulated on its own, the equivalent of Set as current model: each equivalence set then uses its member inside `CellDyn`. With no payload, `CellDyn` grows exactly as `GenericCellDynamics` did in Section 2.2.
cellDynDriver = sbioselect(cellDyn.Variants, "Name", "Drivers for testing standalone model");
isolated = sbiosimulate(cellDyn, getconfigset(cellDyn, "active"), [cellDynDriver, noPayload]);
[~, xIsolated] = selectbyname(isolated, "Tumor.total_cell_subtype");
[~, xGeneric] = selectbyname(withoutPayload, "Tumor.total_cell_subtype");
largestDifference = max(abs(xIsolated - xGeneric))
%[text] ### 3.11 Simulate the parent model again
%[text] Simulating a submodel on its own does not change the connections: `AgPosTumor` still kills its cells.
again = sbiosimulate(agPosTumor);
sameResult = isequal(again.Data, connected.Data)
%[text] ### 3.12 Parameterize the population
%[text] Every quantity specific to this population ends in `_subtype`. Rename them for the population, so that a tumor model with several populations can connect each population's quantities by name: `Tumor.total_cell_subtype` becomes `Tumor.total_cell_AgPosTumor`. In the apps, you export the model to the MATLAB workspace as `m1` first; here it is already the variable `agPosTumor`.
parameterizeModel(agPosTumor, "subtype");
%%
%[text] ## 4.0 Assembling a complex hierarchical model
%[text] ### 4.1 Construct a Tumor Model that aggregates multiple cell population types
%[text] Open the scaffold. Its placeholders for the Ag+ tumor cells are named for the population.
scaffoldProject = sbioloadproject(fullfile(root, "dev", "TumorModel_Scaffold.sbproj"));
tumorModel = scaffoldProject.m1;
%[text] Load the cell populations. Each is built like `AgPosTumor` and already parameterized: its cell count is named for it.
populationsProject = sbioloadproject(fullfile(repository, "CellPopulations.sbproj"));
populations = [populationsProject.m1 populationsProject.m2 populationsProject.m3 populationsProject.m4];
disp(sbioselect(populations, "Type", "species", "Where", "Name", "regexp", "^total_cell_"))
%[text] Move `AgPosTumor` into `TumorModel`.
move(sbioselect(populations, "Name", "AgPosTumor", "Depth", 0), tumorModel);
disp(tumorModel.Models)
%[text] Add `TumorModel`'s cell count to the existing set that `AgPosTumor`'s `CellDyn` and `Binding` share, the equivalent of dragging it onto the set. The set now has a member in `TumorModel`, so the Model Builder shows it under `TumorModel` instead of `AgPosTumor`. Adding a quantity does not change the set's resolved quantity, which stays `CellDyn`'s cell count: `CellDyn` owns the dynamics of the cells, and `TumorModel` only sums them.
cellCountSet = getEquivalenceSet(sbioselect(tumorModel, "Where", "FullyQualifiedName", "==", "TumorModel.AgPosTumor.CellDyn.Tumor.total_cell_AgPosTumor"));
disp(cellCountSet)
add(cellCountSet, sbioselect(tumorModel, "Where", "FullyQualifiedName", "==", "TumorModel.Tumor.total_cell_AgPosTumor"));
disp(cellCountSet)
%[text] Connect the growth rate manually: `TumorModel`'s tumor-wide rate, `k_cell_doubling`, supplies `AgPosTumor`'s `k_self_doubling_for_AgPosTumor`, which has a name of its own. The resolved quantity is the member from the highest model, `TumorModel`.
addequivalence(tumorModel, [sbioselect(tumorModel, "Where", "FullyQualifiedName", "==", "TumorModel.k_cell_doubling")
    sbioselect(tumorModel, "Where", "FullyQualifiedName", "==", "TumorModel.AgPosTumor.CellDyn.k_self_doubling_for_AgPosTumor")]);
%[text] Match by name to connect everything else. Every match is a true match: the shared states and constants, and `AgPosTumor`'s live cell count and cell fraction, whose names are the same as their placeholders in `TumorModel`.
matchByName(tumorModel);
%[text] A set that already existed keeps its resolved quantity, so the sets that `AgPosTumor`'s `CellDyn` and `Binding` already shared are still resolved in `CellDyn`. Make `TumorModel` the resolved quantity for the states shared across the tumor, which it owns or computes, and, as for the total cell count, make `CellDyn`'s live cell count the resolved quantity.
for name = ["Tumor" "Tumor.P" "tumor_volume" "cell_radius" "MOL_UNIT" "AgPosTumor.CellDyn.Tumor.live_cell_AgPosTumor"]
    quantity = sbioselect(tumorModel, "Where", "FullyQualifiedName", "==", "TumorModel." + name);
    eqSet = getEquivalenceSet(quantity, tumorModel);
    eqSet.ResolvedQuantity = quantity;
end
%[text] Turn off the stand-in rule for `tumor_volume`: `TumorModel` now computes it. With both rules active, the model does not verify:
agPosStandalone = sbioselect(tumorModel, "Type", "rule", "Name", "Rule_tumor_volume_standalone");
try
    verify(tumorModel);
catch err
    disp(err.message)
end
agPosStandalone.Active = false;
verify(tumorModel);
%[text] ### 4.2 Combine the PK and PD dynamics into a single `ADCBystander` model
drugProject = sbioloadproject(fullfile(repository, "DrugDispositionModels.sbproj"));
systemicPK = sbioselect([drugProject.m1 drugProject.m2], "Name", "SystemicPK", "Depth", 0);
adcBystander = sbiomodel("ADCBystander");
cs = getconfigset(adcBystander, "active");
cs.StopTime = 168;
cs.TimeUnits = "hour";
cs.SolverOptions.AbsoluteTolerance = 1e-10;
cs.SolverOptions.RelativeTolerance = 1e-8;
cs.CompileOptions.DefaultSpeciesDimension = "substance";
move(systemicPK, adcBystander);
move(tumorModel, adcBystander);
%[text] Match by name to connect the PK and the tumor: the `Tumor` compartment, free ADC and payload, `tumor_volume`, and the ADC's properties.
matchByName(adcBystander);
%[text] Check the resolved quantities with `ADCBystander` as the current model: `SystemicPK` for `Average_DAR` and `k_dc`, and `TumorModel` for the tumor's states.
for name = ["Tumor" "Tumor.P" "tumor_volume" "cell_radius" "MOL_UNIT"]
    quantity = sbioselect(adcBystander, "Where", "FullyQualifiedName", "==", "ADCBystander.TumorModel." + name);
    disp(getEquivalenceSet(quantity, adcBystander).ResolvedQuantity.FullyQualifiedName)
end
%[text] Names in a dose are resolved from the model being simulated, so write each one in full from the root.
dose = getdose(systemicPK, "IV_dose");
dose.TargetName = "ADCBystander.SystemicPK.Central.A";
dose.Amount = "ADCBystander.SystemicPK.dose_amount";
dose.Interval = "ADCBystander.SystemicPK.dose_interval";
dose.RepeatCount = "ADCBystander.SystemicPK.dose_repeat";
%[text] Simulate the dose at several dose levels, the equivalent of the dose slider in the Model Analyzer.
doseLevels = [1 2.7 5.4 10.8];     % mg/kg
cs.RuntimeOptions.StatesToLog = "ADCBystander.TumorModel.tumor_volume";
figure, hold on
for doseLevel = doseLevels
    level = sbiovariant("dose " + doseLevel);
    addcontent(level, {"parameter", "ADCBystander.SystemicPK.dose", "Value", doseLevel});
    [t, x] = selectbyname(sbiosimulate(adcBystander, cs, level, dose), "ADCBystander.TumorModel.tumor_volume");
    plot(t, x)
end
legend(compose("%g mg/kg", doseLevels))
title("ADCBystander, one cell population"), xlabel("Time (hour)"), ylabel("tumor\_volume (liter)")
%[text] ### 4.3 Extend `ADCBystander` to model heterogeneous cell populations
move(sbioselect(populations, "Name", "AgNegTumor", "Depth", 0), tumorModel);
move(sbioselect(populations, "Name", "AgPosStroma", "Depth", 0), tumorModel);
%[text] Add `TumorModel`'s placeholders for the new populations: their cell fractions, cell counts and live cell count.
addparameter(tumorModel, "cell_fraction_AgNegTumor", 0, "Units", "dimensionless");
addparameter(tumorModel, "cell_fraction_AgPosStroma", 0, "Units", "dimensionless");
tumor = sbioselect(tumorModel.Compartments, "Name", "Tumor");
addspecies(tumor, "total_cell_AgNegTumor", 0, "Units", "molecule");
addspecies(tumor, "total_cell_AgPosStroma", 0, "Units", "molecule");
addspecies(tumor, "live_cell_AgNegTumor", 0, "Units", "molecule");
%[text] Update the rules to include the new populations.
rule = sbioselect(tumorModel.Rules, "Name", "Rule_tumor_volume");
rule.Rule = "tumor_volume = (total_cell_AgPosTumor+total_cell_AgNegTumor+total_cell_AgPosStroma+MOL_UNIT)*volume_per_cell/(1-epsilon_payload)";
rule = sbioselect(tumorModel.Rules, "Name", "Rule_total_tumor_live_cell");
rule.Rule = "total_tumor_live_cell = live_cell_AgPosTumor+live_cell_AgNegTumor";
rule = sbioselect(tumorModel.Rules, "Name", "Rule_cell_fraction_tumor");
rule.Rule = "cell_fraction_tumor = cell_fraction_AgPosTumor+cell_fraction_AgNegTumor";
rule = sbioselect(tumorModel.Rules, "Name", "Rule_cell_fraction_stroma");
rule.Rule = "cell_fraction_stroma = cell_fraction_AgPosStroma";
%[text] Turn off the new populations' stand-in rules for `tumor_volume`.
set(sbioselect(tumorModel, "Type", "rule", "Name", "Rule_tumor_volume_standalone"), "Active", false);
%[text] Match by name, then make `AgNegTumor`'s `CellDyn` the resolved quantity for its cell counts. A resolved quantity is chosen for each current model, so do it with both `ADCBystander` and `TumorModel` as the current model; the extracted `TumorModel` keeps the second. (`AgPosStroma`'s cell count joined the set its `CellDyn` and `Binding` already shared, which keeps `CellDyn` as its resolved quantity.)
matchByName(adcBystander);
for name = ["total_cell_AgNegTumor" "live_cell_AgNegTumor"]
    quantity = sbioselect(tumorModel, "Where", "FullyQualifiedName", "==", "ADCBystander.TumorModel.AgNegTumor.CellDyn.Tumor." + name);
    eqSet = getEquivalenceSet(quantity, adcBystander);
    eqSet.ResolvedQuantity = quantity;
    eqSet = getEquivalenceSet(quantity, tumorModel);
    eqSet.ResolvedQuantity = quantity;
end
%[text] Connect the growth rates manually: the tumor-wide growth rate for `AgNegTumor`, added to the existing set, and the stroma's recruited growth rate and recruiting cells for `AgPosStroma`.
kCellDoubling = sbioselect(tumorModel, "Where", "FullyQualifiedName", "==", "ADCBystander.TumorModel.k_cell_doubling");
add(getEquivalenceSet(kCellDoubling), sbioselect(tumorModel, "Where", "FullyQualifiedName", "==", ...
    "ADCBystander.TumorModel.AgNegTumor.CellDyn.k_self_doubling_for_AgNegTumor"));
addequivalence(tumorModel, [sbioselect(tumorModel, "Where", "FullyQualifiedName", "==", "ADCBystander.TumorModel.k_recruited_doubling")
    sbioselect(tumorModel, "Where", "FullyQualifiedName", "==", "ADCBystander.TumorModel.AgPosStroma.CellDyn.k_recruited_doubling_for_AgPosStroma")]);
addequivalence(tumorModel, [sbioselect(tumorModel, "Where", "FullyQualifiedName", "==", "ADCBystander.TumorModel.Tumor.total_tumor_live_cell")
    sbioselect(tumorModel, "Where", "FullyQualifiedName", "==", "ADCBystander.TumorModel.AgPosStroma.CellDyn.Tumor.total_recruiting_cell_for_AgPosStroma")]);
verify(adcBystander);
%[text] Create a variant for each of the paper's three scenarios.
modeled = ["AgPosTumor" "AgNegTumor" "AgPosStroma"];
fractions = [1 0 0; 0.2 0.8 0; 0 0.8 0.2];     % one row per scenario, one column per population
for k = 1:numel(scenarios)
    variant = addvariant(tumorModel, scenarios(k));
    for p = 1:numel(modeled)
        addcontent(variant, {"parameter", "ADCBystander.TumorModel.cell_fraction_" + modeled(p), "Value", fractions(k, p)});
    end
end
%[text] Simulate the three scenarios and plot each population's cells. Only resolved quantities can be logged.
cellCounts = "ADCBystander.TumorModel." + modeled + ".CellDyn.Tumor.total_cell_" + modeled;
cs.RuntimeOptions.StatesToLog = [cellCounts "ADCBystander.TumorModel.tumor_volume"];
figure
tiledlayout(1, numel(scenarios))
built = cell(1, numel(scenarios));
for k = 1:numel(scenarios)
    built{k} = sbiosimulate(adcBystander, cs, sbioselect(tumorModel.Variants, "Name", scenarios(k)), dose);
    [t, x] = selectbyname(built{k}, cellCounts);
    nexttile
    plot(t, x)
    title(scenarios(k)), xlabel("Time (hour)"), ylabel("Cells (molecule)")
end
legend(modeled)
%[text] Extract `TumorModel` for future use: copy it into a project of its own. Its scenario variants name quantities from `ADCBystander`, which is not in the new project, and a variant entry that does not resolve is silently ignored, so remove the `ADCBystander.` prefix.
TumorModel = copyobj(tumorModel);
for variant = TumorModel.Variants'
    content = variant.Content;
    for k = 1:numel(content)
        content{k}{2} = erase(content{k}{2}, "ADCBystander.");
    end
    variant.Content = content;
end
assert(~isfile(extractedProject), "%s already exists.", extractedProject);
sbiosaveproject(extractedProject, "TumorModel");
%[text] The test `dev/tests/tTumorModel.m` checks what the extracted model guarantees.
extractedResults = runtests(fullfile(root, "dev", "tests", "tTumorModel.m"))
%%
%[text] ## 5.0 Validation against a known reference
%[text] ### 5.1 Reopen `dev/assembled/ADCBystander_Assembled.sbproj`
%[text] The assembled model adds a `Drug-to-Antibody Ratio` submodel and reporting aggregates. With the deconjugation rate `k_dc` at 0, they do not change the dynamics, so the model you built above closely matches it. The largest relative difference in tumor volume, for each scenario:
for k = 1:numel(scenarios)
    reference = sbiosimulate(assembled, getconfigset(assembled, "active"), ...
        sbioselect(assembledTumor.Variants, "Name", scenarios(k)), assembledDose);
    [~, xReference] = selectbyname(reference, "ADCBystander.TumorModel.tumor_volume");
    [~, xBuilt] = selectbyname(resample(built{k}, reference.Time), "ADCBystander.TumorModel.tumor_volume");
    disp(scenarios(k) + ": " + max(abs(xBuilt./xReference - 1)))
end
%[text] ### 5.2 Validate against reference or expected results
%[text] The test compares the assembled model with the simulation results of the original flat model, stored in `data/referenceADCBystanderResults.xlsx`.
validationResults = runtests(fullfile(root, "dev", "assembled", "tests", "tADCBystander.m"))
%%
%[text] ## 6.0 Extending a hierarchical model
%[text] **Cell fractions that include all three cell types.** Simulate `TumorModel` on its own with all three populations: add a "Mixed tumor and stroma" variant, and apply it with `TumorModel`'s driver, which supplies the free ADC. Simulating a submodel on its own is the equivalent of Set as current model; names are still full names from the root, `ADCBystander.TumorModel`. Only resolved quantities can be logged, and the cell counts are resolved in each `CellDyn` with `TumorModel` as the current model too (Section 4.3). The Ag- tumor cells, which do not bind the ADC, decline by about the same fraction as the Ag+ cells (bystander killing).
mixed = addvariant(tumorModel, "Mixed tumor and stroma");
mixedFractions = [0.2 0.6 0.2];
for p = 1:numel(modeled)
    addcontent(mixed, {"parameter", "ADCBystander.TumorModel.cell_fraction_" + modeled(p), "Value", mixedFractions(p)});
end
tumorDriver = sbioselect(tumorModel.Variants, "Name", "Drivers for testing standalone model");
cs = getconfigset(tumorModel, "active");
cs.RuntimeOptions.StatesToLog = cellCounts;
[t, x] = selectbyname(sbiosimulate(tumorModel, cs, [tumorDriver, mixed]), cellCounts);
figure
plot(t, x)
legend(modeled)
title("TumorModel on its own, mixed tumor and stroma"), xlabel("Time (hour)"), ylabel("Cells (molecule)")

%[appendix]{"version":"1.0"}
%---
%[metadata:view]
%   data: {"layout":"inline"}
%---
