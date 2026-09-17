function manifest = WriteSibilantContinuum(outDir, opts)
% WriteSibilantContinuum  Write a set of continuum tokens to disk with a manifest.
%
%   manifest = WriteSibilantContinuum("stimuli")
%   manifest = WriteSibilantContinuum("stimuli", 'A', 0:0.125:1, 'Vowels', ["i" "u"], ...
%                                     'Talkers', ["pert6P02" "pert8P01"], 'Seed', 42)
%
% Synthesises every talker x vowel x a combination with SynthSibilant, writes
% <outDir>/<talker>_<vowel>_a<a>.wav (16-bit, 44.1 kHz) and
% <outDir>/manifest.tsv with one row per file: filename, talker, vowel, a,
% seed, template, sibilant and vowel duration (s), sibilant onset and vowel
% onset/offset (samples), sibilant level re. vowel (dB), sibilant peak (Hz,
% mid slice). The manifest is what a presentation script should read.
%
% Options:
%   A         continuum steps (default 0:0.1:1)
%   Vowels    ["i" "u"] (default both)
%   Talkers   string array of ids, or "all" (default) for every model talker
%   Seed      base seed; token (t, v, a) uses Seed + a fixed offset so the
%             noise differs between tokens but the set is reproducible ([] =
%             not reproducible)
%   Template  excitation template index passed to SynthSibilant ([] = random
%             per token, chosen from the seeded stream)
%   Level, PadMs, Model   passed to SynthSibilant

arguments
    outDir (1,1) string
    opts.A (1,:) double = 0:0.1:1
    opts.Vowels (1,:) string = ["i" "u"]
    opts.Talkers string = "all"
    opts.Seed = 1
    opts.Template = []
    opts.Level (1,1) double = -20
    opts.PadMs (1,2) double = [50 50]
    opts.Model = ""
end

if ~isfolder(outDir), mkdir(outDir); end
if isscalar(opts.Talkers) && opts.Talkers == "all"
    talkers = SynthSibilantTalkers(opts.Model);
else
    talkers = opts.Talkers;
end

rows = {};
k = 0;
for t = 1:numel(talkers)
    for v = 1:numel(opts.Vowels)
        for ai = 1:numel(opts.A)
            k = k + 1;
            if isempty(opts.Seed), seed = []; else, seed = opts.Seed + k; end
            [y, Fs, info] = SynthSibilant(opts.A(ai), opts.Vowels(v), talkers(t), ...
                'Seed', seed, 'Template', opts.Template, 'Level', opts.Level, 'PadMs', opts.PadMs, 'Model', opts.Model);
            fname = sprintf("%s_%s_a%.3f.wav", talkers(t), opts.Vowels(v), opts.A(ai));
            audiowrite(fullfile(outDir, fname), y, Fs, 'BitsPerSample', 16);
            rows(end+1, :) = {fname, info.talker, info.vowel, info.a, seed, info.template, ...
                              info.sibDurS, info.vowDurS, info.sibOnset, info.vowOnset, info.vowOffset, ...
                              info.sibLevelDb, info.sibPeakHz(ceil(end/2))}; %#ok<AGROW>
        end
    end
end
if isempty(opts.Seed), rows(:, 5) = {NaN}; end
manifest = cell2table(rows, 'VariableNames', ["filename" "talker" "vowel" "a" "seed" "template" ...
    "sib_dur_s" "vow_dur_s" "sib_onset" "vow_onset" "vow_offset" "sib_level_db" "sib_peak_hz"]);
writetable(manifest, fullfile(outDir, "manifest.tsv"), 'FileType', 'text', 'Delimiter', '\t');
fprintf("wrote %d tokens and manifest.tsv to %s\n", height(manifest), outDir);
end
