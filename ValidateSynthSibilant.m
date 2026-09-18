function V = ValidateSynthSibilant(opts)
% ValidateSynthSibilant  Whole-spectrum validation of the synthesizer over all talkers.
%
%   V = ValidateSynthSibilant()
%   V = ValidateSynthSibilant('Talkers', ["pert6P02" "pert0P01"])
%
% Compares synthetic tokens with the real recordings using the ENTIRE
% mid-sibilant spectrum (not a summary statistic), plus the mid-vowel
% formants:
%
%  1. Real distribution. The experiment's per-trial mid-sibilant mic spectra
%     (extracted_data/participants/*_spectra.tsv; practice + baseline, i.e.
%     unshifted) are put on a 1/12-octave grid, 500 Hz - 16 kHz, and level-
%     normalised (spectrumFeatures) -> one 61-dimensional shape vector per
%     trial.
%  2. Synthetic tokens are synthesised for every talker, both vowels,
%     a = 0:0.1:1, and measured identically (measureMidSpectrum).
%  3. ENDPOINT FIT. For each talker x word, the synthetic endpoint's distance
%     from the talker's real trials of that word is the RMS over bins of
%     (synthetic - real mean) / real SD ("rms z"). For comparison the same
%     quantity is computed for every real trial (leave-one-out). A synthetic
%     endpoint with rms z at or below the real trials' median sits inside the
%     talker's own cloud.
%  4. CONTINUUM. A shrinkage Fisher discriminant (fitSpectrumLda) is trained
%     per vowel on ALL real trials (/sh/ words vs /s/ words, all talkers) and
%     rescaled so the /sh/ class mean scores 0 and the /s/ class mean 1
%     ("ahat"). Applied to the synthetic continuum this gives the whole-
%     spectrum position of every token; ahat(a) should rise monotonically
%     from ~0 to ~1, and the endpoints should fall within the real classes'
%     score distributions. Because talkers differ in where their /sh/ and /s/
%     energy sits, the same tokens are also projected on each TALKER'S OWN
%     axis (real /s/ mean - real /sh/ mean of that talker; "pos"), which is
%     the within-talker whole-spectrum position that a listener hearing one
%     talker would be tracking.
%  5. VOWEL. Mid-vowel F1/F2 of the synthetic endpoints (EstimateFormants,
%     experiment lib, search-range preset from the roster's sex column)
%     vs the talker's real means (all_extracted.tsv). The real means come
%     from the experiment repo's extraction, which uses the same column, so
%     the two sides only match if that extraction was re-run after the
%     column last changed. The
%     endpoints for this check are synthesised with 'VowelContext', "morph"
%     (vowel filter follows the word); the sibilant checks use the default
%     fixed vowel, which does not affect the sibilant.
%
% Writes <OutDir>/validation_all.tsv (one row per talker x vowel) and
% <OutDir>/fig/validation_all.png. Returns a struct with the table and the
% summary statistics printed at the end.
%
% Options: Talkers ("all"), Model, OutDir, ExperimentDir, Seed, AGrid.

arguments
    opts.Talkers string = "all"
    opts.Model (1,1) string = fullfile(fileparts(mfilename('fullpath')), "sibilant_model.mat")
    opts.OutDir (1,1) string = fullfile(fileparts(mfilename('fullpath')), "test_output")
    opts.ExperimentDir (1,1) string = "/Users/plg/github/sibilant_experiment"
    opts.Seed (1,1) double = 1
    opts.AGrid (1,:) double = 0:0.1:1
end

here = fileparts(mfilename('fullpath'));
addpath(fullfile(here, "lib"), fullfile(opts.ExperimentDir, "code", "analysis", "lib"));
S = load(opts.Model, 'model'); M = S.model; Fs = M.Fs;
if isscalar(opts.Talkers) && opts.Talkers == "all", talkers = M.talkerIds; else, talkers = opts.Talkers; end
figDir = fullfile(opts.OutDir, "fig"); if ~isfolder(figDir), mkdir(figDir); end
aGrid = opts.AGrid; nA = numel(aGrid);
clsLab = ["/sh/" "/s/"]; clsCol = ["b" "r"];
roster = readtable(fullfile(opts.ExperimentDir, "participants.tsv"), 'FileType', 'text', 'Delimiter', '\t', 'TextType', 'string');
E = readtable(fullfile(opts.ExperimentDir, "extracted_data", "all_extracted.tsv"), 'FileType', 'text', 'Delimiter', '\t', 'TextType', 'string');
E = E(ismember(E.block, ["practice" "baseline"]) & ismember(E.participant, talkers), :);

%% 1. real spectra
fprintf("Loading real spectra of %d talkers ...\n", numel(talkers));
R = loadRealSpectra(talkers, opts.ExperimentDir);
R.vowel = M.vowelOf(arrayfun(@(t) find(M.tokens == t, 1), R.token)).';
R.isS   = M.classOf(arrayfun(@(t) find(M.tokens == t, 1), R.token)).' == "s";

%% 2. synthesise + measure
fprintf("Synthesising %d tokens ...\n", numel(talkers) * 2 * nA);
nT = numel(talkers);
Xs = zeros(nT, 2, nA, size(R.X, 2));         % talker x vowel x a x feature
F12 = nan(nT, 2, 2, 2);                       % talker x vowel x endpoint x [F1 F2]
vowels = ["i" "u"];
for i = 1:nT
    sex = roster.sex(roster.participant == talkers(i));
    for v = 1:2
        for ai = 1:nA
            [y, ~, info] = SynthSibilant(aGrid(ai), vowels(v), talkers(i), 'Model', M, 'Seed', opts.Seed, 'Template', 1);
            [dB, fHz] = measureMidSpectrum(y(info.sibOnset:info.vowOnset), Fs);
            Xs(i, v, ai, :) = spectrumFeatures(fHz, dB);
            if ai == 1 || ai == nA                    % vowel check: coarticulating vowel
                [y, ~, info] = SynthSibilant(aGrid(ai), vowels(v), talkers(i), 'Model', M, 'Seed', opts.Seed, 'Template', 1, 'VowelContext', "morph");
                F12(i, v, 1 + (ai == nA), :) = midFormants(y(info.vowOnset:info.vowOffset), Fs, sex);
            end
        end
    end
    if mod(i, 10) == 0, fprintf("  %d/%d\n", i, nT); end
end

%% 3. endpoint fit, 4. continuum, 5. vowel  -> table
rows = cell(nT * 2, 1); L = struct();
for v = 1:2
    sel = R.vowel == vowels(v);
    L(v).lda = fitSpectrumLda(R.X(sel, :), R.isS(sel));
end
for i = 1:nT
    for v = 1:2
        words = M.tokens(M.vowelOf == vowels(v));
        row = struct('talker', talkers(i), 'vowel', vowels(v));
        for w = 1:2
            sel = R.talker == talkers(i) & R.token == words(w);
            Xr = R.X(sel, :); mu = mean(Xr, 1); sd = std(Xr, 0, 1) + 1;   % +1 dB floor
            xs = squeeze(Xs(i, v, 1 + (w == 2) * (nA - 1), :)).';
            zSynth = rms((xs - mu) ./ sd);
            n = size(Xr, 1); zReal = zeros(n, 1);
            for k = 1:n                                                 % leave-one-out
                o = true(n, 1); o(k) = false;
                zReal(k) = rms((Xr(k, :) - mean(Xr(o, :), 1)) ./ (std(Xr(o, :), 0, 1) + 1));
            end
            row.("z_synth_" + w) = zSynth;
            row.("z_real_med_" + w) = median(zReal);
            row.("z_real_p90_" + w) = quantile(zReal, 0.9);
            row.("n_real_" + w) = n;
            % real class score distribution for this talker/word
            sc = applySpectrumLda(L(v).lda, Xr);
            row.("ahat_real_mean_" + w) = mean(sc); row.("ahat_real_sd_" + w) = std(sc);
            % vowel formants
            Et = E(E.participant == talkers(i) & E.token == words(w), :);
            row.("F1_synth_" + w) = F12(i, v, w, 1); row.("F2_synth_" + w) = F12(i, v, w, 2);
            row.("F1_real_" + w) = mean(Et.vow_f1, 'omitnan'); row.("F2_real_" + w) = mean(Et.vow_f2, 'omitnan');
        end
        ah = applySpectrumLda(L(v).lda, squeeze(Xs(i, v, :, :)));
        row.ahat = ah(:).';
        row.ahat_monotonic = all(diff(ah) > 0);
        row.ahat_sh = ah(1); row.ahat_s = ah(end);
        % talker's own axis
        mu0 = mean(R.X(R.talker == talkers(i) & R.token == words(1), :), 1);
        mu1 = mean(R.X(R.talker == talkers(i) & R.token == words(2), :), 1);
        ax = mu1 - mu0;
        ps = ((squeeze(Xs(i, v, :, :)) - mu0) * ax.') / (ax * ax.');
        row.pos = ps(:).';
        row.pos_monotonic = all(diff(ps) > 0);
        row.pos_sh = ps(1); row.pos_s = ps(end);
        row.pos_step_min = min(diff(ps)); row.pos_step_max = max(diff(ps));
        rows{(i - 1) * 2 + v} = row;
    end
end
rows = [rows{:}];
Tb = struct2table(rows);
ahatAll = cat(1, rows.ahat); Tb.ahat = [];
posAll = cat(1, rows.pos); Tb.pos = [];
Tb = movevars(Tb, ["pos_sh" "pos_s" "pos_monotonic" "ahat_sh" "ahat_s" "ahat_monotonic"], 'After', 'vowel');
writetable(Tb, fullfile(opts.OutDir, "validation_all.tsv"), 'FileType', 'text', 'Delimiter', '\t');

%% summary
fprintf("\n================ whole-spectrum validation, %d talkers ================\n", nT);
for v = 1:2
    fprintf("vowel /%s/: real-trial LDA accuracy (sh vs s, %d trials) = %.1f%%\n", vowels(v), nnz(R.vowel == vowels(v)), 100 * L(v).lda.accuracy);
end
fprintf("\nENDPOINT FIT (rms z of the synthetic endpoint from the talker's real cloud; real trials' leave-one-out median for scale)\n");
for w = 1:2
    zs = Tb.("z_synth_" + w); zr = Tb.("z_real_med_" + w); zp = Tb.("z_real_p90_" + w);
    fprintf("  %s endpoint: synthetic rms z median %.2f (IQR %.2f-%.2f); real trials' median %.2f; synthetic below real median in %.0f%%, below real 90th pct in %.0f%% of talker x vowel cells\n", ...
        clsLab(w), median(zs), quantile(zs, .25), quantile(zs, .75), median(zr), 100 * mean(zs < zr), 100 * mean(zs < zp));
end
fprintf("\nCONTINUUM (ahat: whole-spectrum discriminant position, 0 = real /sh/ mean, 1 = real /s/ mean)\n");
fprintf("  ahat at a=0: median %.2f (IQR %.2f-%.2f);  at a=1: median %.2f (IQR %.2f-%.2f)\n", ...
    median(Tb.ahat_sh), quantile(Tb.ahat_sh, .25), quantile(Tb.ahat_sh, .75), median(Tb.ahat_s), quantile(Tb.ahat_s, .25), quantile(Tb.ahat_s, .75));
fprintf("  real per-talker class means: /sh/ words %.2f +- %.2f, /s/ words %.2f +- %.2f (mean +- sd over talker x vowel)\n", ...
    mean([Tb.ahat_real_mean_1]), std([Tb.ahat_real_mean_1]), mean([Tb.ahat_real_mean_2]), std([Tb.ahat_real_mean_2]));
fprintf("  monotonic ahat(a) in %.0f%% of talker x vowel cells; mean ahat by a: %s\n", 100 * mean(Tb.ahat_monotonic), mat2str(round(mean(ahatAll, 1), 2)));
fprintf("\nCONTINUUM on each talker's OWN /sh/ -> /s/ spectral axis (pos: 0 = that talker's real /sh/ mean, 1 = real /s/ mean)\n");
fprintf("  pos at a=0: median %.2f (IQR %.2f-%.2f);  at a=1: median %.2f (IQR %.2f-%.2f)\n", ...
    median(Tb.pos_sh), quantile(Tb.pos_sh, .25), quantile(Tb.pos_sh, .75), median(Tb.pos_s), quantile(Tb.pos_s, .25), quantile(Tb.pos_s, .75));
fprintf("  monotonic pos(a) in %.0f%% of cells; step per 0.1 in a: min %.2f / max %.2f (median over cells); mean pos by a: %s\n", ...
    100 * mean(Tb.pos_monotonic), median(Tb.pos_step_min), median(Tb.pos_step_max), mat2str(round(mean(posAll, 1), 2)));
fprintf("\nVOWEL (mid-vowel formants, synthetic endpoint vs talker's real mean; Hz)\n");
for w = 1:2
    d1 = Tb.("F1_synth_" + w) - Tb.("F1_real_" + w); d2 = Tb.("F2_synth_" + w) - Tb.("F2_real_" + w);
    fprintf("  after %s: F1 error median %+.0f (MAD %.0f), F2 error median %+.0f (MAD %.0f); F2 measurable in %.0f%% of synthetic tokens\n", ...
        clsLab(w), median(d1, 'omitnan'), mad(d1, 1), median(d2, 'omitnan'), mad(d2, 1), 100 * mean(~isnan(Tb.("F2_synth_" + w))));
end

%% figure
fig = figure('Visible', 'off', 'Position', [0 0 1500 900]);
tl = tiledlayout(fig, 2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tl, sprintf("SynthSibilant whole-spectrum validation, %d talkers", nT));
for v = 1:2
    nexttile; hold on
    sel = Tb.vowel == vowels(v);
    plot(aGrid, ahatAll(sel, :).', 'Color', [0 0 0 0.15], 'HandleVisibility', 'off');
    plot(aGrid, mean(ahatAll(sel, :), 1), 'k', 'LineWidth', 2.5, 'DisplayName', 'population discriminant (mean)');
    plot(aGrid, mean(posAll(sel, :), 1), 'Color', [0 0.6 0], 'LineWidth', 2.5, 'DisplayName', 'talker''s own axis (mean)');
    yline(0, 'b--', 'HandleVisibility', 'off'); yline(1, 'r--', 'HandleVisibility', 'off');
    sc0 = L(v).lda.ahatReal(~R.isS(R.vowel == vowels(v))); sc1 = L(v).lda.ahatReal(R.isS(R.vowel == vowels(v)));
    errorbar(-0.04, mean(sc0), std(sc0), 'bs', 'LineWidth', 2, 'MarkerFaceColor', 'b', 'DisplayName', 'real /sh/ trials');
    errorbar(1.04, mean(sc1), std(sc1), 'rs', 'LineWidth', 2, 'MarkerFaceColor', 'r', 'DisplayName', 'real /s/ trials');
    xlabel('a'); ylabel('whole-spectrum position (ahat)'); grid on; xlim([-0.1 1.1]);
    title(sprintf('vowel /%s/: whole-spectrum position (grey: talkers; squares: real trials)', vowels(v)));
    legend('Location', 'northwest');
end
nexttile; hold on
for w = 1:2
    zs = Tb.("z_synth_" + w); zr = Tb.("z_real_med_" + w);
    scatter(zr, zs, 30, clsCol(w), 'filled', 'MarkerFaceAlpha', 0.6, 'DisplayName', clsLab(w) + " endpoints");
end
lim = [0 max([Tb.z_synth_1; Tb.z_synth_2; Tb.z_real_med_1; Tb.z_real_med_2]) * 1.1];
plot(lim, lim, 'k--', 'DisplayName', 'equal'); xlim(lim); ylim(lim); axis square
xlabel('real trials'' median rms z (leave-one-out)'); ylabel('synthetic endpoint rms z'); grid on; legend('Location', 'northwest');
title('endpoint fit to the talker''s own trial cloud');
for w = 1:2
    nexttile; hold on
    scatter(Tb.("F2_real_" + w), Tb.("F2_synth_" + w), 30, 'k', 'filled', 'MarkerFaceAlpha', 0.6, 'DisplayName', 'F2');
    scatter(Tb.("F1_real_" + w), Tb.("F1_synth_" + w), 30, [0.5 0.5 0.5], 'filled', 'MarkerFaceAlpha', 0.6, 'DisplayName', 'F1');
    plot([0 3000], [0 3000], 'k--', 'HandleVisibility', 'off'); axis square; xlim([0 3000]); ylim([0 3000]);
    xlabel('real mean (Hz)'); ylabel('synthetic (Hz)'); grid on; legend('Location', 'northwest');
    title(sprintf('mid-vowel formants after %s (both vowels)', clsLab(w)));
end
nexttile; hold on
grid_ = spectrumFeatureGrid();
i = 1;
for w = 1:2
    words = M.tokens(M.vowelOf == "i");
    sel = R.talker == talkers(i) & R.token == words(w);
    mu = mean(R.X(sel, :), 1); sd = std(R.X(sel, :), 0, 1);
    c = clsCol(w);
    fill([grid_ fliplr(grid_)], [mu + sd fliplr(mu - sd)], c, 'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    plot(grid_, mu, c, 'LineWidth', 2, 'DisplayName', "real " + words(w) + " mean +- sd");
    plot(grid_, squeeze(Xs(i, 1, 1 + (w == 2) * (nA - 1), :)), c + ":", 'LineWidth', 2, 'DisplayName', "synthetic a=" + (w - 1));
end
set(gca, 'XScale', 'log'); xlim([500 16000]); grid on; legend('Location', 'southwest'); xlabel('Hz'); ylabel('dB (level-normalised)');
title(sprintf('example: %s, vowel /i/', talkers(i)), 'Interpreter', 'none');
exportgraphics(fig, fullfile(figDir, "validation_all.png"), 'Resolution', 100);
close(fig);

V.table = Tb; V.ahat = ahatAll; V.pos = posAll; V.aGrid = aGrid; V.lda = L; V.real = R;
fprintf("\nwrote %s and %s\n", fullfile(opts.OutDir, "validation_all.tsv"), fullfile(figDir, "validation_all.png"));
end

%% ------------------------------------------------------------------------
function f12 = midFormants(vow, Fs, sex)
[fm, t, conf] = EstimateFormants(vow, Fs, 'gender', char(sex));
f1 = fm(:, 2); f2 = fm(:, 3);
f1(conf(:, 2) < 0.4) = NaN; f2(conf(:, 3) < 0.4) = NaN;
tau = t / (numel(vow) / Fs); sel = tau >= 0.4 & tau <= 0.6;
f12 = [median(f1(sel), 'omitnan'), median(f2(sel), 'omitnan')];
end
