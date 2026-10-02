function R = loadRealSpectra(talkers, experimentDir)
% loadRealSpectra  Real mid-sibilant mic spectra of unshifted trials.
%
%   R = loadRealSpectra(talkers, experimentDir)
%
% Reads extracted_data/participants/<pid>_spectra.tsv (written by the
% experiment's extract_spectra; point "m", channel "mic", practice and
% baseline blocks) for the given talkers. Returns a struct with
%   talker, token   (nTrials x 1 string)
%   fHz             1 x nF, the 40 Hz grid
%   dB              nTrials x nF
%   X               nTrials x nGrid whole-spectrum features (spectrumFeatures)
dir_ = fullfile(experimentDir, "extracted_data", "participants");
parts = cell(numel(talkers), 1);
for i = 1:numel(talkers)
    f = fullfile(dir_, talkers(i) + "_spectra.tsv");
    if ~isfile(f)
        error("loadRealSpectra:missing", "%s not found: run extract_spectra(""%s"") in the experiment repo.", f, talkers(i));
    end
    T = readtable(f, 'FileType', 'text', 'Delimiter', '\t', 'TextType', 'string');
    T = T(T.point == "m" & T.channel == "mic" & ismember(T.block, ["practice" "baseline"]), :);
    parts{i} = T;
end
T = vertcat(parts{:});
isF = startsWith(T.Properties.VariableNames, "f_");
R.talker = T.participant;
R.token  = T.token;
R.fHz    = double(erase(string(T.Properties.VariableNames(isF)), "f_"));
R.dB     = T{:, isF};
R.X      = spectrumFeatures(R.fHz, R.dB);
end
