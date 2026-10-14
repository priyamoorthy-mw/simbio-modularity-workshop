function sets = matchByName(parent)
%MATCHBYNAME  Connect every set of same-named quantities below a parent
%             model, as Auto-match by name does in the Model Builder.
%
%   matchByName(AgPosTumor)
%
% Compartments and parameters match by name, and species by compartment
% and name (Tumor.P), anywhere in parent and its submodels. A quantity
% tagged "local" is internal to its model and is never matched. Each match
% becomes one equivalence set owned by parent:
%   - if none of its quantities is in a set yet, a new set
%     (addequivalence);
%   - if some are, the rest are added to that set, merging the sets first
%     if there are several. As in the Model Builder, a set that is extended
%     keeps its resolved quantity.
% Prints each set it creates or extends, with its resolved quantity, and
% returns them.
arguments
    parent (1,1) SimBiology.Model
end

quantities = [sbioselect(parent, "Type", "compartment"); sbioselect(parent, "Type", "parameter")
    sbioselect(parent, "Type", "species")];
quantities = quantities(arrayfun(@(q) ~any(string(q.Tags) == "local"), quantities));
keys = arrayfun(@qualifiedName, quantities);

sets = SimBiology.EquivalenceSet.empty;
for key = unique(keys, "stable")'
    matched = quantities(keys == key);
    if numel(matched) < 2
        continue
    end
    existing = setsContaining(parent, matched);
    loose = matched(arrayfun(@(q) ~any(arrayfun(@(e) isMember(e, q), existing)), matched));
    if isempty(existing)
        eqSet = addequivalence(parent, loose);
    elseif isscalar(existing) && isempty(loose)
        continue                                    % already connected
    else
        eqSet = existing(1);
        if numel(existing) > 1
            eqSet = merge(eqSet, existing(2:end));
        end
        if ~isempty(loose)
            eqSet = add(eqSet, loose);
        end
    end
    sets(end + 1, 1) = eqSet; %#ok<AGROW>
    fprintf("%s: %s (resolved %s)\n", parent.Name, key, eqSet.ResolvedQuantity.FullyQualifiedName);
end
end

function name = qualifiedName(quantity)
% A quantity's name within its own model: a species by compartment.species.
name = string(quantity.Name);
if quantity.Type == "species"
    name = string(quantity.Parent.Name) + "." + name;
end
end

function sets = setsContaining(parent, quantities)
% The distinct top-level sets, owned by parent or below it, that contain
% any of the quantities.
sets = SimBiology.EquivalenceSet.empty;
ids = strings(0);
for e = parent.EquivalenceSets'
    top = e.TopLevelSet;
    if ~any(ids == string(top.UUID)) && any(arrayfun(@(q) isMember(top, q), quantities))
        sets(end + 1, 1) = top; %#ok<AGROW>
        ids(end + 1) = string(top.UUID); %#ok<AGROW>
    end
end
end

function tf = isMember(eqSet, quantity)
tf = any([eqSet.Quantities.SessionID] == quantity.SessionID);
end
