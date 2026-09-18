function model = BuildSibilantModel(opts)
% BuildSibilantModel  Learn per-talker sibilant + vowel models from the recordings.
%
%   model = BuildSibilantModel()                                  % all eligible talkers
%   model = BuildSibilantModel('Talkers', ["pert6P02" "pert8P01"], ...
%                              'OutFile', "test_model.mat")
%
% Reads the sibilant_experiment raw audio (microphone channel) together with
% the hand-scored boundaries (scored_data/<pid>_scored.tsv: sibilant onset,
% sibilant end = vowel onset, vowel end, in samples) for every UNSHIFTED trial
% (practice and baseline blocks) of the four words she / see / shoe / sue, and
% summarises each talker x word as:
%
%   SIBILANT
%     sibSpecDb   NSibSlices x nLog   mean (in linear power) multitaper
%                                     spectrum, in dB, at equally spaced points
%                                     across the normalised sibilant, on a
%                                     1/48-octave log grid, lightly smoothed
%     sibPeakHz   1 x NSibSlices      main spectral peak per slice: centroid
%                                     (log f) of the region within 6 dB of
%                                     the in-band maximum -- the landmark
%                                     used to morph /sh/ -> /s/
%     sibEnvDb    1 x NEnv            RMS envelope over normalised time (dB
%                                     re. the whole-sibilant RMS)
%     sibDurS                         median duration (s)
%     sibLevelDb                      mean 20*log10(rms sibilant / rms vowel)
%   VOWEL
%     vowLsf      NVowFrames x LpcOrder  vocal-tract filter per normalised-time
%                                     frame, as line spectral frequencies (rad)
%                                     averaged across trials (LSF averaging
%                                     keeps formant bandwidths, unlike
%                                     averaging spectra)
%     vowRmsDb    1 x NVowFrames      RMS contour (dB re. whole-vowel RMS)
%     vowDurS                         median vowel duration (s)
%     vowF0Hz                         median mid-vowel F0 (Hz)
%     vowSpecDb   1 x nLog            mean mid-vowel multitaper spectrum (dB),
%                                     for validation only
%
% and, per talker x vowel, NTemplates LPC-residual excitation signals taken
% from the she / shoe recordings whose vowel duration is closest to the median.
% SynthSibilant.m drives the interpolated vocal-tract filter with these.
%
% Talkers: every participant in participants.tsv whose cohort recorded all four
% words -- the ryan cohort (no practice block, hence no see/sue) is excluded,
% as is any talker with fewer than MinTrials usable trials of some word.
%
% Options (name, value):
%   RawDir, ScoredDir, ParticipantsFile   data locations (defaults below)
%   Talkers        "all" or string array of participant ids
%   OutFile        where to save the model ("" = do not save)
%   Fs             model sampling rate (44100); other rates are resampled
%   NSibSlices     spectral slices across the sibilant (5)
%   SibWinMs       multitaper window (40 ms), 7 tapers
%   NEnv           points in the sibilant RMS envelope (25)
%   NVowFrames     LPC frames across the vowel (40)
%   LpcOrder       LPC order at Fs (40)
%   PreEmph        pre-emphasis coefficient for LPC (0.97)
%   NTemplates     residual excitation templates per talker x vowel (2)
%   MinTrials      minimum usable trials per word (3)
%   UseParallel    parfor over talkers if the toolbox is present (true)
%
% Requires Signal Processing Toolbox (pmtm, lpc, poly2lsf).

arguments
    opts.RawDir (1,1) string = "/Users/plg/Library/CloudStorage/Dropbox/data/sibilant_experiment/raw_data"
    opts.ScoredDir (1,1) string = "/Users/plg/github/sibilant_experiment/scored_data"
    opts.ParticipantsFile (1,1) string = "/Users/plg/github/sibilant_experiment/participants.tsv"
    opts.Talkers string = "all"
    opts.OutFile (1,1) string = fullfile(fileparts(mfilename('fullpath')), "sibilant_model.mat")
    opts.Fs (1,1) double = 44100
    opts.NSibSlices (1,1) double = 5
    opts.SibWinMs (1,1) double = 40
    opts.NEnv (1,1) double = 25
    opts.NVowFrames (1,1) double = 40
    opts.LpcOrder (1,1) double = 40
    opts.PreEmph (1,1) double = 0.97
    opts.NTemplates (1,1) double = 2
    opts.MinTrials (1,1) double = 3
    opts.UseParallel (1,1) logical = true
end

t0 = tic;

%% Constants shared with SynthSibilant via the model struct
P = struct();
P.Fs         = opts.Fs;
P.tokens     = ["she" "see" "shoe" "sue"];
P.vowelOf    = ["i"   "i"   "u"    "u"];
P.classOf    = ["sh"  "s"   "sh"   "s"];
P.nSlices    = opts.NSibSlices;
P.sibWin     = round(opts.SibWinMs / 1000 * P.Fs);
P.nEnv       = opts.NEnv;
P.nVowFrames = opts.NVowFrames;
P.lpcOrder   = opts.LpcOrder;
P.preEmph    = opts.PreEmph;
P.lpcWin     = round(0.030 * P.Fs);          % 30 ms LPC analysis window
P.lpcHop     = round(0.005 * P.Fs);          % 5 ms
P.logGridHz  = 2 .^ (log2(100):(1/48):log2(P.Fs/2));   % 1/48 octave, 100 Hz .. Nyquist
P.smoothOct  = 1/24;                         % Gaussian sigma for sibilant spectra
P.peakBandHz = struct('sh', [1800 5000], 's', [3000 10000]);  % landmark search bands
P.minSibDurS = 0.060;
P.minVowDurS = 0.080;
P.nTemplates = opts.NTemplates;

%% Roster
R = readtable(opts.ParticipantsFile, 'FileType', 'text', 'Delimiter', '\t', 'TextType', 'string');
eligible = R.group ~= "ryan";
if ~(isscalar(opts.Talkers) && opts.Talkers == "all")
    unknown = setdiff(opts.Talkers, R.participant);
    if ~isempty(unknown)
        error("BuildSibilantModel:unknownTalker", "Unknown participant id(s): %s", strjoin(unknown, ", "));
    end
    eligible = eligible & ismember(R.participant, opts.Talkers);
end
R = R(eligible, :);
nT = height(R);
fprintf("BuildSibilantModel: %d candidate talkers\n", nT);

%% Per-talker analysis
talkers = cell(nT, 1);
usepar = opts.UseParallel && license('test', 'Distrib_Computing_Toolbox') && ~isempty(ver('parallel'));
rawDir = opts.RawDir; scoredDir = opts.ScoredDir; minTrials = opts.MinTrials;
if usepar
    parfor i = 1:nT
        talkers{i} = analyzeTalker(R.participant(i), R.group(i), R.sex(i), rawDir, scoredDir, P, minTrials);
    end
else
    for i = 1:nT
        talkers{i} = analyzeTalker(R.participant(i), R.group(i), R.sex(i), rawDir, scoredDir, P, minTrials);
        fprintf("  [%d/%d] %s  (%.0f s elapsed)\n", i, nT, R.participant(i), toc(t0));
    end
end
ok = ~cellfun(@isempty, talkers);
if any(~ok)
    fprintf("Excluded (too few usable trials of some word): %s\n", strjoin(R.participant(~ok), ", "));
end
talkers = [talkers{ok}];

model = P;
model.version = "1.0";
model.built   = string(datetime('now'));
model.talkerIds = [talkers.id];
model.talkers = talkers;

if strlength(opts.OutFile) > 0
    save(opts.OutFile, 'model', '-v7');
    fprintf("Saved %d talkers to %s (%.0f s)\n", numel(talkers), opts.OutFile, toc(t0));
end
end

%% ========================================================================
function T = analyzeTalker(pid, group, sex, rawDir, scoredDir, P, minTrials)
% Analyse one participant; returns [] if some word has too few usable trials.
T = [];
scoredFile = fullfile(scoredDir, pid + "_scored.tsv");
if ~isfile(scoredFile)
    warning("BuildSibilantModel:noScored", "%s: no scored file, skipped.", pid);
    return
end
S = readtable(scoredFile, 'FileType', 'text', 'Delimiter', '\t', 'TextType', 'string');
wavDir = fullfile(rawDir, group, pid);

% keep unshifted (practice P / baseline B) trials of the four words
parts = arrayfun(@(f) split(erase(f, ".wav"), "_"), S.filename, 'UniformOutput', false);
tok   = cellfun(@(p) p(end-5), parts);
phase = cellfun(@(p) p(end-4), parts);
keep  = ismember(phase, ["P" "B"]) & ismember(tok, P.tokens) & ...
        isfinite(S.sib_start) & isfinite(S.sib_end) & isfinite(S.vow_end) & S.sib_start > 0;
S = S(keep, :); tok = tok(keep);

% analyse every trial
n = height(S);
tr = cell(n, 1);
for k = 1:n
    tr{k} = analyzeTrial(fullfile(wavDir, S.filename(k)), S.sib_start(k), S.sib_end(k), S.vow_end(k), P);
end
good = ~cellfun(@isempty, tr);
tr = tr(good); tok = tok(good);

% aggregate per word
words = cell(1, numel(P.tokens));
for j = 1:numel(P.tokens)
    these = [tr{tok == P.tokens(j)}];
    if numel(these) < minTrials
        warning("BuildSibilantModel:fewTrials", "%s: only %d usable '%s' trials, talker skipped.", pid, numel(these), P.tokens(j));
        return
    end
    words{j} = aggregateWord(these, P.classOf(j), P);
    words{j}.token = P.tokens(j);
end
words = [words{:}];

% excitation templates from the /sh/ words, one set per vowel
vowels = unique(P.vowelOf, 'stable');
templ = cell(1, numel(vowels));
for v = 1:numel(vowels)
    j = find(P.vowelOf == vowels(v) & P.classOf == "sh", 1);
    these = [tr{tok == P.tokens(j)}];
    these = these(words(j).included);
    [~, order] = sort(abs([these.vowDurS] - words(j).vowDurS));
    pick = these(order(1:min(P.nTemplates, numel(these))));
    templ{v} = struct('vowel', vowels(v), 'token', P.tokens(j), ...
        'residual', {arrayfun(@(t) single(t.residual), pick, 'UniformOutput', false)}, ...
        'vowDurS', [pick.vowDurS], 'f0Hz', [pick.f0Hz], 'source', [pick.file]);
end
templ = [templ{:}];

T = struct('id', pid, 'group', group, 'sex', sex, 'words', words, 'templates', templ, ...
           'nTrials', numel(tr));
end

%% ========================================================================
function r = analyzeTrial(wavFile, s0, s1, v1, P)
% Measurements from one trial. Boundaries in samples of the recording.
r = [];
[x, fs] = audioread(wavFile);
x = x(:, 1);                                          % channel 1 = microphone
if fs ~= P.Fs
    x = resample(x, P.Fs, fs);
    s0 = round(s0 * P.Fs / fs); s1 = round(s1 * P.Fs / fs); v1 = round(v1 * P.Fs / fs);
end
s0 = max(1, round(s0)); s1 = round(s1); v1 = min(numel(x), round(v1));
if s1 - s0 < P.minSibDurS * P.Fs || v1 - s1 < P.minVowDurS * P.Fs || max(abs(x)) > 0.99
    return
end
x = x - mean(x);
sib = x(s0:s1);
vow = x(s1:v1);

r.file    = string(wavFile);
r.sibDurS = numel(sib) / P.Fs;
r.vowDurS = numel(vow) / P.Fs;
r.sibLevelDb = 20 * log10(rms(sib) / rms(vow));

% --- sibilant: time-varying multitaper spectra on the log grid
r.sibSpecDb = zeros(P.nSlices, numel(P.logGridHz));
W = P.sibWin; nfft = 4096;
for k = 1:P.nSlices
    c = s0 + (k - 0.5) / P.nSlices * (s1 - s0);
    head = max(s0, round(c - W/2)); tail = min(s1, head + W - 1); head = tail - W + 1;
    [pxx, f] = pmtm(x(head:tail), 4, nfft, P.Fs);    % 7 Slepian tapers
    r.sibSpecDb(k, :) = 10 * log10(interp1(f, pxx, P.logGridHz, 'linear', 'extrap'));
end

% --- sibilant RMS envelope over normalised time
r.sibEnvDb = rmsContour(sib, round(0.010 * P.Fs), P.nEnv);

% --- vowel: LPC envelopes and RMS contour on normalised-time frames
vp = filter([1 -P.preEmph], 1, vow);
r.vowLsf = zeros(P.nVowFrames, P.lpcOrder);
Wl = min(P.lpcWin, numel(vp)); win = hamming(Wl);
for m = 1:P.nVowFrames
    c = (m - 0.5) / P.nVowFrames * numel(vp);
    head = max(1, round(c - Wl/2)); tail = min(numel(vp), head + Wl - 1); head = tail - Wl + 1;
    a = lpc(vp(head:tail) .* win, P.lpcOrder);
    if any(isnan(a)), a = [1 zeros(1, P.lpcOrder)]; end
    r.vowLsf(m, :) = poly2lsf(a).';
end
r.vowRmsDb = rmsContour(vow, round(0.025 * P.Fs), P.nVowFrames);

% --- mid-vowel F0 (normalised autocorrelation) and multitaper spectrum
mid = round(numel(vow) / 2); half = round(0.020 * P.Fs);
seg = vow(max(1, mid - half):min(numel(vow), mid + half));
r.f0Hz = estimateF0(seg, P.Fs);
[pxx, f] = pmtm(seg, 4, nfft, P.Fs);
r.vowSpecDb = 10 * log10(interp1(f, pxx, P.logGridHz, 'linear', 'extrap'));

% --- LPC residual of the whole vowel (excitation template candidate)
r.residual = lpcResidual(vp, P);
end

%% ------------------------------------------------------------------------
function W = aggregateWord(tr, cls, P)
% Combine the trials of one word into the model summary, with outlier rejection.
sibDur = [tr.sibDurS]; vowDur = [tr.vowDurS]; lev = [tr.sibLevelDb];
inc = true(size(sibDur));
if numel(tr) >= 10                                    % MAD is unreliable on 5 trials
    inc = ~robustOutlier(sibDur) & ~robustOutlier(vowDur) & ~robustOutlier(lev);
    if nnz(inc) < 3, inc(:) = true; end
end
tr = tr(inc);
W.n = numel(tr);
W.included = inc;
W.sibDurS   = median([tr.sibDurS]);
W.vowDurS   = median([tr.vowDurS]);
W.sibLevelDb = mean([tr.sibLevelDb]);
W.vowF0Hz   = median([tr.f0Hz], 'omitnan');

% sibilant spectra: mean in linear power (the PSD a noise process with these
% trials' statistics would have), to dB, then Gaussian smoothing along log f
spec = 10 * log10(mean(10 .^ (cat(3, tr.sibSpecDb) / 10), 3));
sig = P.smoothOct * 48;                               % bins
g = exp(-0.5 * ((-ceil(3*sig):ceil(3*sig)) / sig).^2); g = g / sum(g);
for k = 1:P.nSlices
    spec(k, :) = conv(padarray1(spec(k, :), numel(g)), g, 'valid');
end
W.sibSpecDb = spec;
band = P.peakBandHz.(cls);
inBand = P.logGridHz >= band(1) & P.logGridHz <= band(2);
W.sibPeakHz = zeros(1, P.nSlices);
ub = log2(P.logGridHz(inBand));
for k = 1:P.nSlices
    % landmark = power-weighted log-frequency centroid of the bins within
    % 6 dB of the in-band maximum (stable when the peak is a broad plateau)
    v = spec(k, inBand); sel = v >= max(v) - 6; w = 10 .^ (v(sel) / 10);
    W.sibPeakHz(k) = 2 ^ (sum(w .* ub(sel)) / sum(w));
end
W.sibEnvDb = mean(cat(1, tr.sibEnvDb), 1);

% vowel: mean LSF per frame (ordered vectors average to an ordered, hence
% stable, vector; formant bandwidths are preserved far better than by
% averaging spectra and refitting)
W.vowLsf = mean(cat(3, tr.vowLsf), 3);
W.vowRmsDb  = mean(cat(1, tr.vowRmsDb), 1);
W.vowSpecDb = mean(cat(1, tr.vowSpecDb), 1);
end

%% ------------------------------------------------------------------------
function e = lpcResidual(vp, P)
% Time-varying inverse filtering (5 ms blocks, 30 ms analysis windows).
n = numel(vp); Wl = min(P.lpcWin, n); win = hamming(Wl);
e = zeros(n, 1); zi = zeros(P.lpcOrder, 1);
for head = 1:P.lpcHop:n
    tail = min(n, head + P.lpcHop - 1);
    c = (head + tail) / 2;
    ah = max(1, round(c - Wl/2)); at = min(n, ah + Wl - 1); ah = at - Wl + 1;
    a = lpc(vp(ah:at) .* win, P.lpcOrder);
    if any(isnan(a)), a = [1 zeros(1, P.lpcOrder)]; end
    [e(head:tail), zi] = filter(a, 1, vp(head:tail), zi);
end
end

function c = rmsContour(x, win, nOut)
% RMS (dB re. overall RMS) at nOut equally spaced normalised-time points.
n = numel(x); c = zeros(1, nOut); win = min(win, n);
for m = 1:nOut
    ctr = (m - 0.5) / nOut * n;
    head = max(1, round(ctr - win/2)); tail = min(n, head + win - 1); head = tail - win + 1;
    c(m) = rms(x(head:tail));
end
c = 20 * log10(max(c, eps) / rms(x));
end

function f0 = estimateF0(seg, fs)
seg = seg(:) .* hann(numel(seg));
[acf, lags] = xcorr(seg, 'coeff');
acf = acf(lags >= 0);
lo = round(fs / 400); hi = min(round(fs / 70), numel(acf) - 1);
[pk, i] = max(acf(lo+1:hi+1));
f0 = fs / (lo + i - 1);
if pk < 0.3, f0 = NaN; end
end

function tf = robustOutlier(v)
med = median(v); s = 1.4826 * median(abs(v - med));
if s == 0, tf = false(size(v)); return; end
tf = abs(v - med) > 3 * s;
end

function y = padarray1(x, n)
% Replicate-pad a row vector by floor(n/2) at each end (for 'valid' conv).
h = floor(n / 2);
y = [repmat(x(1), 1, h), x, repmat(x(end), 1, h)];
end
