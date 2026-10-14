function renameSuffix(model, oldSuffix, newSuffix)
%RENAMESUFFIX  Rename each of a model's own components whose name ends in
%              _<oldSuffix> to end in _<newSuffix> instead.
%
%   renameSuffix(liver, "organ", "Liver");   % Q_organ -> Q_Liver
%
% Renames the model's compartments, species, parameters, rules, reactions
% and observables, but not those of its submodels. Renaming a component
% updates the expressions that use it; the model's own variants are
% updated here, since a variant entry naming the old name would otherwise
% be silently ignored. Prints each rename.
arguments
    model (1,1) SimBiology.Model
    oldSuffix (1,1) string
    newSuffix (1,1) string
end

pattern = "_" + oldSuffix + "$";
renames = dictionary(string.empty, string.empty);
groups = {model.Compartments, vertcat(model.Compartments.Species), model.Parameters, ...
    model.Rules, model.Reactions, model.Observables};
for group = groups(~cellfun(@isempty, groups))
    components = group{1};
    for component = components(endsWith(string({components.Name}), "_" + oldSuffix))'
        oldName = string(component.Name);
        newName = regexprep(oldName, pattern, "_" + newSuffix);
        rename(component, newName);
        renames(oldName) = newName;
        fprintf("%s: %s -> %s\n", model.Name, oldName, newName);
    end
end

if numEntries(renames) > 0
    for variant = model.Variants'
        variant.Content = cellfun(@(entry) renamedEntry(entry, renames), variant.Content, ...
            "UniformOutput", false);
    end
end
end

function entry = renamedEntry(entry, renames)
% entry, with each part of its dotted name that was renamed replaced: the
% component itself, or the compartment of a species.
names = split(string(entry{2}), ".");
isRenamed = isKey(renames, names);
names(isRenamed) = renames(names(isRenamed));
entry{2} = char(join(names, "."));
end
