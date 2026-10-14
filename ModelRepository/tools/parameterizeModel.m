function parameterizeModel(model, suffix, options)
%PARAMETERIZEMODEL  Make copied templates specific to where they are used:
%                   in a model and every submodel below it, every component
%                   whose name ends in _<suffix> takes a model's name in
%                   place of the suffix.
%
%   parameterizeModel(AgPosTumor, "subtype")
%   parameterizeModel(TumorModel, "subtype", NameFrom="parent")
%
% AgPosTumor's CellDyn and Binding are copies of GenericCellDynamics and
% GenericBinding, which name everything specific to one cell population
% with the suffix _subtype. With the default, NameFrom="root", every
% component of the model passed in (the root) and of each of its
% descendants takes the root's name:
%
%   AgPosTumor.CellDyn.Tumor.total_cell_subtype  ->  ...Tumor.total_cell_AgPosTumor
%   AgPosTumor.Binding.Tumor.total_cell_subtype  ->  ...Tumor.total_cell_AgPosTumor
%   AgPosTumor.CellDyn.kill_max_subtype          ->  ...kill_max_AgPosTumor
%
% With NameFrom="parent", each descendant's components take the name of
% the model directly above it instead, so one call parameterizes every
% population in a tumor model; the root itself, which has no parent here,
% is left as it is:
%
%   TumorModel.AgPosTumor.CellDyn.Tumor.total_cell_subtype  ->  ...total_cell_AgPosTumor
%   TumorModel.AgNegTumor.CellDyn.Tumor.total_cell_subtype  ->  ...total_cell_AgNegTumor
%
% Each placeholder now has the name of the quantity that supplies it, so
% connecting by name pairs it with, for example, TumorModel's
% total_cell_AgPosTumor, and does not offer to join AgPosTumor's cells to
% AgNegTumor's. A quantity tagged "local" is not meant to be shared outside
% its model; its new name is one no other model has.
%
% A model with nothing ending in _<suffix>, such as one already
% parameterized, is left as it is. See renameSuffix for what is renamed.
arguments
    model (1,1) SimBiology.Model
    suffix (1,1) string
    options.NameFrom (1,1) string {mustBeMember(options.NameFrom, ["root" "parent"])} = "root"
end

descendants = sbioselect(model, "Type", "sbiomodel");
descendants = descendants(arrayfun(@(m) m.SessionID ~= model.SessionID, descendants));
if options.NameFrom == "root"
    for m = [model; descendants(:)]'
        renameSuffix(m, suffix, model.Name);
    end
else
    for m = descendants(:)'
        renameSuffix(m, suffix, m.Parent.Name);
    end
end
end
