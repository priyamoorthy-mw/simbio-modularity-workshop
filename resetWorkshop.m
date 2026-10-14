function resetWorkshop(options)
%RESETWORKSHOP  Return the workshop files to their starting state, removing
%               the work done while following the guide.
%
%   resetWorkshop
%   resetWorkshop(RestoreRepository=true)
%   resetWorkshop(Confirm=false)
%
% Close the workshop's projects in the Model Builder and Model Analyzer
% first. resetWorkshop lists what it will do and asks before doing it:
%
%   - Copies the starting scaffold, dev/assembled/TumorModel_Scaffold.sbproj,
%     back to dev/TumorModel_Scaffold.sbproj.
%   - Deletes the projects you create in dev while following the guide:
%     TumorModel.sbproj and ADC_Workshop.sbproj, and any project
%     named for AgPosTumor or ADCBystander (such as ADCBystander.sbproj or
%     ADCBystander_Assembled.sbproj). The reference versions stay in
%     dev/assembled.
%   - Deletes TumorModel and its test, if you promoted them to
%     ModelRepository (TumorModel.sbproj and tests/tTumorModel.m).
%   - Deletes the backups (*.sbproj.bak) the Model Builder saves next to
%     projects.
%
% Options (name=value):
%   RestoreRepository  also discard changes to the files the workshop
%                      provides (ModelRepository, dev/assembled and data),
%                      restoring them as they were last committed. This
%                      discards any uncommitted change to those files,
%                      including your own (default false).
%   Confirm            ask before making any change (default true)
arguments
    options.RestoreRepository (1,1) logical = false
    options.Confirm (1,1) logical = true
end

root = string(fileparts(mfilename("fullpath")));
dev = fullfile(root, "dev");
repository = fullfile(root, "ModelRepository");

scaffold = fullfile(dev, "assembled", "TumorModel_Scaffold.sbproj");
assert(isfile(scaffold), "resetWorkshop:noScaffold", "The starting scaffold %s is missing.", scaffold);

toDelete = [
    filesIn(dev, ["TumorModel.sbproj" "ADC_Workshop.sbproj" "AgPosTumor*.sbproj" "ADCBystander*.sbproj"])
    filesIn(repository, "TumorModel.sbproj")
    filesIn(fullfile(repository, "tests"), "tTumorModel.m")
    filesIn(root, "**/*.sbproj.bak")];
toRestore = strings(0, 1);
if options.RestoreRepository
    toRestore = changedWorkshopFiles(root);
end

fprintf("resetWorkshop will:\n");
fprintf("  copy %s\n    to %s\n", relative(root, scaffold), relative(root, fullfile(dev, "TumorModel_Scaffold.sbproj")));
fprintf("  delete %s\n", relative(root, toDelete));
fprintf("  restore %s\n", relative(root, toRestore));
if options.Confirm && ~startsWith(lower(strtrim(string(input("Continue? (y/n) ", "s")))), "y")
    fprintf("Nothing changed.\n");
    return
end

copyfile(scaffold, fullfile(dev, "TumorModel_Scaffold.sbproj"), "f");
for file = toDelete'
    delete(file);
end
if ~isempty(toRestore)
    discardChanges(gitrepo(root), toRestore);
end
fprintf("The workshop is reset.\n");
end

% -------------------------------------------------------------------------

function files = filesIn(folder, patterns)
% The full paths of the files in folder that match any of the patterns.
files = strings(0, 1);
for pattern = patterns
    found = dir(fullfile(folder, pattern));
    found = found(~[found.isdir]);
    files = [files; string(fullfile({found.folder}, {found.name}))']; %#ok<AGROW>
end
files = unique(files);
end

function files = changedWorkshopFiles(root)
% The files the workshop provides that have uncommitted changes.
files = string(gitrepo(root).ModifiedFiles);
provided = startsWith(files, fullfile(root, ["ModelRepository" fullfile("dev", "assembled") "data"]) + filesep);
files = files(provided);
files = files(:);
end

function names = relative(root, files)
% Paths relative to the repository root, for display.
if isempty(files)
    names = "(nothing)";
else
    names = strjoin(erase(files, root + filesep), newline + "         ");
end
end
