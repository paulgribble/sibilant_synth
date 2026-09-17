function R = TestSynthSibilant(opts)
% TestSynthSibilant  Synthesise continua and check them against the recordings.
%
%   R = TestSynthSibilant()                              % 3 talkers, default model
%   R = TestSynthSibilant('Talkers', "pert6P02", 'Model', "test_model.mat")
%
% For each talker and vowel this
%   1. synthesises the continuum a = 0:0.1:1 (fixed noise seed) and writes the
%      WAVs to <OutDir>/wav/<talker>_<vowel>_a<a>.wav for listening;
%   2. measures each synthetic sibilant the way the experiment does (three
%      50 ms multitaper windows at mid-sibilant, lib/measureMidSpectrum) and
%      compares the WHOLE level-normalised spectrum (1/12 octave, 500 Hz -
%      16 kHz) with the talker's real trials of the two words
%      (extracted_data/participants/<pid>_spectra.tsv): endpoint spectra
%      against the real mean +- sd, and every token's position along the
%      talker's own /sh/ -> /s/ spectral-difference axis (0 = real /sh/ mean,
%      1 = real /s/ mean), which should rise monotonically with a;
%   3. tracks F1/F2 of the synthetic vowel (EstimateFormants from the
%      experiment's lib) at a = 0 and a = 1 and compares them with the mean
%      tracks of the talker's real she/see (shoe/sue) vowels, to check that
%      the vowel is realistic and that the /sh/-vs-/s/ coarticulatory
%      difference is carried over;
%   4. saves figures to <OutDir>/fig: spectrograms of the endpoints and
%      midpoint, sibilant spectra along the continuum, endpoint spectra vs the
%      real clouds, whole-spectrum position vs a, and the F1/F2 tracks.
%
% Returns a table R with one row per talker x vowel: whole-spectrum position
% of the endpoints, synthetic and real mid-vowel F1/F2 for both words, and the
% F2-onset difference between the two words (synthetic vs real).
% ValidateSynthSibilant does the same over all talkers without figures.
%
% Options: Talkers ("auto" = 3 talkers spread over the model), Model (path),
% OutDir (default test_output next to this file), ExperimentDir, RawDir, Seed.

arguments
    opts.Talkers string = "auto"
    opts.Model (1,1) string = fullfile(fileparts(mfilename('fullpath')), "sibilant_model.mat")
    opts.OutDir (1,1) string = fullfile(fileparts(mfilename('fullpath')), "test_output")
    opts.ExperimentDir (1,1) string = "/Users/plg/github/sibilant_experiment"
    opts.RawDir (1,1) string = "/Users/plg/Library/CloudStorage/Dropbox/data/sibilant_experiment/raw_data"
    opts.Seed (1,1) double = 1
end

S = load(opts.Model, 'model'); M = S.model; Fs = M.Fs;
addpath(fullfile(fileparts(mfilename('fullpath')), "lib"), fullfile(opts.ExperimentDir, "code", "analysis", "lib"));
wavDir = fullfile(opts.OutDir, "wav"); figDir = fullfile(opts.OutDir, "fig");
if ~isfolder(wavDir), mkdir(wavDir); end
if ~isfolder(figDir), mkdir(figDir); end
if isscalar(opts.Talkers) && opts.Talkers == "auto"
    n = numel(M.talkerIds);
    talkers = M.talkerIds(unique(round(linspace(1, n, min(3, n)))));
else
    talkers = opts.Talkers;
end
E = readtable(fullfile(opts.ExperimentDir, "extracted_data", "all_extracted.tsv"), ...
              'FileType', 'text', 'Delimiter', '\t', 'TextType', 'string');
E = E(ismember(E.block, ["practice" "baseline"]), :);
Rs = loadRealSpectra(talkers, opts.ExperimentDir);           % real mid-sibilant spectra
gridF = spectrumFeatureGrid();
roster = readtable(fullfile(opts.ExperimentDir, "participants.tsv"), 'FileType', 'text', 'Delimiter', '\t', 'TextType', 'string');

aGrid = 0:0.1:1;
rows = {};
for talker = talkers
    T = M.talkers(M.talkerIds == talker);
    for vowel = ["i" "u"]
        words = M.tokens(M.vowelOf == vowel);            % [sh-word s-word]
        fprintf("\n=== %s, vowel %s (%s -> %s) ===\n", talker, vowel, words(1), words(2));

        % ---- 1. continuum -> WAVs, 2. sibilant measures
        Y = cell(size(aGrid)); I = cell(size(aGrid));
        specRendered = zeros(numel(aGrid), numel(M.logGridHz));
        Xs = zeros(numel(aGrid), numel(gridF));
        for ai = 1:numel(aGrid)
            [y, ~, info] = SynthSibilant(aGrid(ai), vowel, talker, 'Model', M, 'Seed', opts.Seed, 'Template', 1);
            audiowrite(fullfile(wavDir, sprintf("%s_%s_a%.1f.wav", talker, vowel, aGrid(ai))), y, Fs);
            Y{ai} = y; I{ai} = info;
            [dB, fHz] = measureMidSpectrum(y(info.sibOnset:info.vowOnset), Fs);
            Xs(ai, :) = spectrumFeatures(fHz, dB);
            specRendered(ai, :) = interp1(fHz, dB, M.logGridHz, 'linear', 'extrap');
        end
        % real clouds and the talker's own /sh/ -> /s/ axis
        Xr = cell(1, 2); mu = zeros(2, numel(gridF)); sd = mu;
        for w = 1:2
            Xr{w} = Rs.X(Rs.talker == talker & Rs.token == words(w), :);
            mu(w, :) = mean(Xr{w}, 1); sd(w, :) = std(Xr{w}, 0, 1);
        end
        axis_ = mu(2, :) - mu(1, :);
        pos = @(X) ((X - mu(1, :)) * axis_.') / (axis_ * axis_.');
        ahat = pos(Xs);
        realPos = {pos(Xr{1}), pos(Xr{2})};
        zEnd = [rms((Xs(1, :) - mu(1, :)) ./ (sd(1, :) + 1)), rms((Xs(end, :) - mu(2, :)) ./ (sd(2, :) + 1))];
        fprintf("whole-spectrum position (0 = real %s mean, 1 = real %s mean):\n", words(1), words(2));
        fprintf("  synthetic a = 0:0.1:1 -> %s   monotonic: %d\n", mat2str(round(ahat.', 2)), all(diff(ahat) > 0));
        fprintf("  real %s trials: %.2f +- %.2f (n=%d); real %s trials: %.2f +- %.2f (n=%d)\n", ...
                words(1), mean(realPos{1}), std(realPos{1}), numel(realPos{1}), words(2), mean(realPos{2}), std(realPos{2}), numel(realPos{2}));
        fprintf("  endpoint rms z from the real cloud: a=0 %.2f, a=1 %.2f (a real trial: ~1)\n", zEnd(1), zEnd(2));

        % ---- 3. vowel formants: synthetic endpoints vs real mean tracks
        gender = roster.gender(roster.participant == talker);
        nTau = 20;
        synthTracks = zeros(2, nTau, 2);   % word x tau x [F1 F2]
        for w = 1:2
            info = I{(w-1)*(numel(aGrid)-1)+1}; y = Y{(w-1)*(numel(aGrid)-1)+1};
            vow = y(info.vowOnset:info.vowOffset);
            synthTracks(w, :, :) = formantTrack(vow, Fs, gender, nTau);
        end
        realTracks = zeros(2, nTau, 2); realN = zeros(1, 2);
        for w = 1:2
            [realTracks(w, :, :), realN(w)] = realFormantTracks(talker, words(w), opts, roster, Fs, gender, nTau);
        end
        midSel = round(nTau * 0.4):round(nTau * 0.6);
        synthMid = squeeze(mean(synthTracks(:, midSel, :), 2, 'omitnan'));  % word x [F1 F2]
        realMid  = squeeze(mean(realTracks(:, midSel, :), 2, 'omitnan'));
        onSel = 1:3;
        synthOn = squeeze(mean(synthTracks(:, onSel, :), 2, 'omitnan'));
        realOn  = squeeze(mean(realTracks(:, onSel, :), 2, 'omitnan'));
        for w = 1:2
            fprintf("%-4s vowel mid  F1/F2: synth %4.0f/%4.0f  real %4.0f/%4.0f (n=%d)    onset F2: synth %4.0f  real %4.0f\n", ...
                words(w), synthMid(w, 1), synthMid(w, 2), realMid(w, 1), realMid(w, 2), realN(w), synthOn(w, 2), realOn(w, 2));
        end
        fprintf("F2 onset difference (%s - %s): synth %+.0f Hz, real %+.0f Hz\n", words(2), words(1), ...
                synthOn(2, 2) - synthOn(1, 2), realOn(2, 2) - realOn(1, 2));

        rows(end+1, :) = {talker, vowel, ahat(1), ahat(end), all(diff(ahat) > 0), zEnd(1), zEnd(2), ...
                          synthMid(1,1), synthMid(1,2), realMid(1,1), realMid(1,2), ...
                          synthMid(2,1), synthMid(2,2), realMid(2,1), realMid(2,2), ...
                          synthOn(2,2)-synthOn(1,2), realOn(2,2)-realOn(1,2)}; %#ok<AGROW>

        % ---- 4. figures
        fig = figure('Visible', 'off', 'Position', [0 0 1500 1300]);
        tl = tiledlayout(fig, 4, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
        title(tl, sprintf("%s  vowel /%s/  (%s -> %s)", talker, vowel, words(1), words(2)), 'Interpreter', 'none');
        for ai = [1 6 11]
            nexttile; y = Y{ai};
            spectrogram(y, hann(512), 448, 1024, Fs, 'yaxis'); colorbar off; ylim([0 12]);
            clim([-130 -50]); title(sprintf("a = %.1f", aGrid(ai)));
        end
        nexttile; hold on
        cols = parula(numel(aGrid) + 1);
        for ai = 1:numel(aGrid)
            plot(M.logGridHz, specRendered(ai, :), 'Color', cols(ai, :), 'LineWidth', 1.2);
        end
        set(gca, 'XScale', 'log'); xlim([200 22050]); grid on; xlabel('Hz'); ylabel('dB');
        title('rendered mid-sibilant spectra, a = 0 (blue) .. 1 (yellow)');
        nexttile; hold on
        jsh = find(M.tokens == words(1)); js = find(M.tokens == words(2));
        plot(M.logGridHz, T.words(jsh).sibSpecDb(3, :), 'b', 'LineWidth', 2, 'DisplayName', 'model ' + words(1));
        plot(M.logGridHz, T.words(js).sibSpecDb(3, :), 'r', 'LineWidth', 2, 'DisplayName', 'model ' + words(2));
        plot(M.logGridHz, specRendered(1, :) - mean(specRendered(1, :) - T.words(jsh).sibSpecDb(3, :)), 'b:', 'LineWidth', 1.5, 'DisplayName', 'rendered a=0');
        plot(M.logGridHz, specRendered(end, :) - mean(specRendered(end, :) - T.words(js).sibSpecDb(3, :)), 'r:', 'LineWidth', 1.5, 'DisplayName', 'rendered a=1');
        set(gca, 'XScale', 'log'); xlim([200 22050]); grid on; legend('Location', 'southwest'); xlabel('Hz'); ylabel('dB (level-matched)');
        title('endpoint fidelity: model target vs rendered');
        nexttile; hold on
        for w = 1:2
            c = ["b" "r"]; c = c(w);
            fill([gridF fliplr(gridF)], [mu(w, :) + sd(w, :), fliplr(mu(w, :) - sd(w, :))], c, 'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');
            plot(gridF, mu(w, :), c, 'LineWidth', 2, 'DisplayName', "real " + words(w) + " (mean +- sd, n=" + size(Xr{w}, 1) + ")");
        end
        plot(gridF, Xs(1, :), 'b:', 'LineWidth', 2, 'DisplayName', 'synthetic a=0');
        plot(gridF, Xs(end, :), 'r:', 'LineWidth', 2, 'DisplayName', 'synthetic a=1');
        set(gca, 'XScale', 'log'); xlim([500 16000]); grid on; legend('Location', 'southwest'); xlabel('Hz'); ylabel('dB (level-normalised)');
        title('whole spectrum: synthetic endpoints vs real trial clouds');
        nexttile; hold on
        plot(aGrid, ahat, 'k.-', 'LineWidth', 1.5, 'MarkerSize', 14, 'DisplayName', 'synthetic');
        errorbar(-0.04, mean(realPos{1}), std(realPos{1}), 'bs', 'LineWidth', 2, 'MarkerFaceColor', 'b', 'DisplayName', 'real ' + words(1));
        errorbar(1.04, mean(realPos{2}), std(realPos{2}), 'rs', 'LineWidth', 2, 'MarkerFaceColor', 'r', 'DisplayName', 'real ' + words(2));
        xlabel('a (0 = /sh/, 1 = /s/)'); ylabel('whole-spectrum position'); grid on; legend('Location', 'northwest'); xlim([-0.1 1.1]);
        title('position on the talker''s /sh/ -> /s/ spectral axis');
        tau = ((1:nTau) - 0.5) / nTau;
        for f = 1:2
            nexttile; hold on
            plot(tau, squeeze(realTracks(1, :, f)), 'b-', 'LineWidth', 2, 'DisplayName', 'real ' + words(1));
            plot(tau, squeeze(realTracks(2, :, f)), 'r-', 'LineWidth', 2, 'DisplayName', 'real ' + words(2));
            plot(tau, squeeze(synthTracks(1, :, f)), 'b--o', 'LineWidth', 1.2, 'DisplayName', 'synth a=0');
            plot(tau, squeeze(synthTracks(2, :, f)), 'r--o', 'LineWidth', 1.2, 'DisplayName', 'synth a=1');
            xlabel('normalised vowel time'); ylabel(sprintf('F%d (Hz)', f)); grid on; legend('Location', 'best');
            title(sprintf('vowel F%d: real mean tracks vs synthetic endpoints', f));
        end
        nexttile; hold on
        tt = (0:numel(Y{1})-1) / Fs;
        plot(tt, Y{1}, 'b'); plot((0:numel(Y{end})-1) / Fs, Y{end} - 0.6, 'r');
        xlabel('s'); title('waveforms: a = 0 (top), a = 1 (bottom)'); set(gca, 'YTick', []);
        exportgraphics(fig, fullfile(figDir, sprintf("%s_%s.png", talker, vowel)), 'Resolution', 100);
        close(fig);
    end
end

R = cell2table(rows, 'VariableNames', ["talker" "vowel" "pos_synth_sh" "pos_synth_s" "pos_monotonic" "z_end_sh" "z_end_s" ...
    "F1_synth_sh" "F2_synth_sh" "F1_real_sh" "F2_real_sh" "F1_synth_s" "F2_synth_s" "F1_real_s" "F2_real_s" ...
    "dF2onset_synth" "dF2onset_real"]);
writetable(R, fullfile(opts.OutDir, "validation.tsv"), 'FileType', 'text', 'Delimiter', '\t');
fprintf("\nWAVs in %s\nfigures in %s\n", wavDir, figDir);
end

%% ------------------------------------------------------------------------
function tr = formantTrack(vow, Fs, gender, nTau)
% F1/F2 over normalised time (nTau bins) from EstimateFormants.
[fm, t, conf] = EstimateFormants(vow, Fs, 'gender', char(gender));
f1 = fm(:, 2); f2 = fm(:, 3);
f1(conf(:, 2) < 0.4) = NaN; f2(conf(:, 3) < 0.4) = NaN;
tau = t / (numel(vow) / Fs);
tr = nan(nTau, 2);
for k = 1:nTau
    sel = tau >= (k-1)/nTau & tau < k/nTau;
    tr(k, 1) = median(f1(sel), 'omitnan'); tr(k, 2) = median(f2(sel), 'omitnan');
end
end

function [tr, n] = realFormantTracks(talker, word, opts, roster, Fs, gender, nTau)
% Mean F1/F2 tracks over the talker's real unshifted recordings of one word.
group = roster.group(roster.participant == talker);
Sc = readtable(fullfile(opts.ExperimentDir, "scored_data", talker + "_scored.tsv"), 'FileType', 'text', 'Delimiter', '\t', 'TextType', 'string');
parts = arrayfun(@(f) split(erase(f, ".wav"), "_"), Sc.filename, 'UniformOutput', false);
tok = cellfun(@(p) p(end-5), parts); phase = cellfun(@(p) p(end-4), parts);
Sc = Sc(tok == word & ismember(phase, ["P" "B"]) & isfinite(Sc.sib_end) & isfinite(Sc.vow_end), :);
Sc = Sc(1:min(height(Sc), 12), :);                      % a dozen trials is plenty for a mean track
acc = zeros(nTau, 2); cnt = zeros(nTau, 2); n = 0;
for k = 1:height(Sc)
    [x, fs] = audioread(fullfile(opts.RawDir, group, talker, Sc.filename(k)));
    vow = x(round(Sc.sib_end(k)):round(Sc.vow_end(k)), 1);
    if fs ~= Fs, vow = resample(vow, Fs, fs); end
    tr = formantTrack(vow, Fs, gender, nTau);
    ok = ~isnan(tr); acc(ok) = acc(ok) + tr(ok); cnt = cnt + ok; n = n + 1;
end
tr = acc ./ max(cnt, 1); tr(cnt == 0) = NaN;
end
