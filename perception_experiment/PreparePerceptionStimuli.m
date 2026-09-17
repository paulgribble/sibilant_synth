function S = PreparePerceptionStimuli(stimDir, talkers, vowels, A, opts)
% PreparePerceptionStimuli  Make sure the WAVs an experiment needs exist; synthesise the missing ones.
%
%   S = PreparePerceptionStimuli(stimDir, talkers, vowels, A)
%   S = PreparePerceptionStimuli("../stimuli", "pert6P02", ["i" "u"], 0:0.25:1)
%
% For every talker x vowel x a the file <stimDir>/<talker>_<vowel>_a<a>.wav
% (the WriteSibilantContinuum naming, a with 3 decimals) is looked up. Files
% that already exist are left alone. Missing ones are synthesised in one
% batch with SynthSibilant, using the WriteSibilantContinuum defaults
% (Template 1, VowelContext 0.5, Level -20 dBFS, PadMs [50 50]) so they match
% a set written by it, and a row per new file is appended to
% <stimDir>/manifest.tsv (created if absent; left untouched, with a warning,
% if its columns are not the WriteSibilantContinuum ones). The noise seed of
% a new token is derived from its file name, so regenerating a deleted file
% gives the same token whatever else is requested.
%
% RunPerceptionExperiment calls this before the first trial; nothing is
% synthesised during the experiment. To run an experiment on tokens made
% with other synthesis options, write them with WriteSibilantContinuum into
% a folder of their own and pass that folder as StimDir.
%
% Options:
%   Regenerate  true = synthesise every requested token again, overwriting
%               the WAVs (use after a change to the synthesis; default false)
%   Model       passed to SynthSibilant
%
% Output: table S, one row per requested token: filename, path, talker,
% vowel, a, existed (false = synthesised by this call).
%
% See also RunPerceptionExperiment, WriteSibilantContinuum, SynthSibilant.

arguments
    stimDir (1,1) string
    talkers (1,:) string
    vowels (1,:) string
    A (1,:) double
    opts.Regenerate (1,1) logical = false
    opts.Model = ""
end

addpath(fileparts(fileparts(mfilename('fullpath'))));    % SynthSibilant & co.
if ~isfolder(stimDir), mkdir(stimDir); end

rows = {};
for t = 1:numel(talkers)
    for v = 1:numel(vowels)
        for ai = 1:numel(A)
            fname = sprintf("%s_%s_a%.3f.wav", talkers(t), vowels(v), A(ai));
            rows(end+1, :) = {fname, fullfile(stimDir, fname), talkers(t), vowels(v), A(ai)}; %#ok<AGROW>
        end
    end
end
S = cell2table(rows, 'VariableNames', ["filename" "path" "talker" "vowel" "a"]);
S.existed = isfile(S.path) & ~opts.Regenerate;

todo = find(~S.existed);
if isempty(todo)
    fprintf("stimuli: all %d tokens found in %s\n", height(S), stimDir);
    return
end

fprintf("stimuli: %d of %d tokens to synthesise in %s ...\n", numel(todo), height(S), stimDir);
known = SynthSibilantTalkers(opts.Model);
bad = setdiff(unique(S.talker(todo)), known);
if ~isempty(bad)
    error("PreparePerceptionStimuli:unknownTalker", ...
          "Talker(s) not in the model: %s. See SynthSibilantTalkers.", strjoin(bad, ", "));
end

mrows = {};
for k = todo(:)'
    seed = nameSeed(S.filename(k));
    [y, Fs, info] = SynthSibilant(S.a(k), S.vowel(k), S.talker(k), ...
        'Seed', seed, 'Template', 1, 'VowelContext', 0.5, 'Level', -20, 'PadMs', [50 50], 'Model', opts.Model);
    audiowrite(S.path(k), y, Fs, 'BitsPerSample', 16);
    mrows(end+1, :) = {S.filename(k), string(info.talker), string(info.vowel), info.a, seed, info.template, info.vowelA, ...
                       info.sibDurS, info.vowDurS, info.sibOnset, info.vowOnset, info.vowOffset, ...
                       info.sibLevelDb, info.sibPeakHz(ceil(end/2))}; %#ok<AGROW>
end
fprintf("stimuli: wrote %d WAVs\n", numel(todo));

% manifest: replace the rows of rewritten files, append the new ones
names = ["filename" "talker" "vowel" "a" "seed" "template" "vowel_context" ...
         "sib_dur_s" "vow_dur_s" "sib_onset" "vow_onset" "vow_offset" "sib_level_db" "sib_peak_hz"];
new = cell2table(mrows, 'VariableNames', names);
mfile = fullfile(stimDir, "manifest.tsv");
if isfile(mfile)
    old = readtable(mfile, 'FileType', 'text', 'Delimiter', '\t', 'TextType', 'string');
    if ~isequal(string(old.Properties.VariableNames), names)
        warning("PreparePerceptionStimuli:manifest", ...
                "%s does not have the WriteSibilantContinuum columns; not updated.", mfile);
        return
    end
    old(ismember(old.filename, new.filename), :) = [];
    new = [old; new];
end
writetable(new, mfile, 'FileType', 'text', 'Delimiter', '\t');
end

% -------------------------------------------------------------------------
function seed = nameSeed(fname)
% deterministic 31-bit seed from a file name
c = double(char(fname));
seed = mod(sum(c .* (1:numel(c))) * 7919, 2^31 - 1);
end
