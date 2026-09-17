function [y, Fs, info] = SynthSibilant(a, vowel, talker, opts)
% SynthSibilant  Synthesise a sibilant + vowel token on a /sh/ -- /s/ continuum.
%
%   [y, Fs, info] = SynthSibilant(a, vowel)                 % random talker
%   [y, Fs, info] = SynthSibilant(a, vowel, talker)         % e.g. "pert6P02"
%   [y, Fs, info] = SynthSibilant(a, vowel, talker, Name, Value, ...)
%
%   a       0.0 = pure /sh/ ... 1.0 = pure /s/ (any value in between)
%   vowel   "i" (she / see) or "u" (shoe / sue)
%   talker  "random" (default) or a participant id from the model
%           (see SynthSibilantTalkers)
%
% The token is built from a data-driven talker model (sibilant_model.mat, made
% by BuildSibilantModel from the sibilant_experiment recordings):
%
%   SIBILANT  White noise shaped, frame by frame, by a time-varying spectral
%             envelope. At a = 0 / 1 the envelope is the talker's mean /sh/ or
%             /s/ spectrum IN THE REQUESTED VOWEL CONTEXT (she vs shoe, see vs
%             sue), measured at 5 points across the sibilant, so the
%             anticipatory labialisation before /u/ is reproduced. In between,
%             the two spectra are MORPHED, not mixed: the frequency axis is
%             warped (piecewise-linear on the mel scale) so that the main
%             spectral peaks are aligned at an interpolated position, and the
%             levels are then linearly interpolated. The peak therefore glides
%             continuously from the /sh/ to the /s/ frequency in EQUAL MEL
%             STEPS per unit a (i.e. equal steps of a are perceptually equal
%             steps in frequency), and the intermediate spectra stay
%             unimodal. Duration (log-linear), RMS
%             envelope and level relative to the vowel are interpolated too.
%
%   VOWEL     A time-varying all-pole (LPC) vocal-tract filter, stored as line
%             spectral frequencies over normalised time, driven by a real LPC
%             residual from one of the talker's own recordings (so pitch,
%             voice quality and breathiness are the talker's). The filter is
%             a weighted interpolation of the talker's mean vowel after /sh/
%             and after /s/, the weight being set by VowelContext. By DEFAULT
%             (VowelContext = 0.5) the weight is fixed halfway, so the vowel
%             is IDENTICAL at every a and the continuum differs only in the
%             sibilant: the listener gets a single cue, and the fixed vowel
%             carries no more evidence for one category than for the other.
%             With VowelContext = "morph" the weight is a itself, so the
%             coarticulatory difference between the vowel of "she" and of
%             "see" (mainly the formant onsets) moves with the sibilant. The
%             RMS contour follows the same weight. Vowel duration and F0 are
%             those of the excitation template (fixed for a given talker x
%             vowel x template).
%
% Options (name, value):
%   VowelContext  which vowel filter to use (default 0.5):
%                 a number in [0, 1]: fixed vowel, the interpolation at that
%                   weight between the /sh/-context (0) and /s/-context (1)
%                   vowel, for every a. 0.5 (default) is neutral; 0 is the
%                   talker's she/shoe vowel (30 trials), 1 the see/sue vowel
%                   (5 trials, noisier).
%                 "sh" / "mid" / "s": aliases for 0 / 0.5 / 1.
%                 "morph": the weight follows a (coarticulation co-varies
%                   with the sibilant).
%   Model     path to the model .mat, or the loaded model struct
%             (default: sibilant_model.mat next to this file; cached)
%   Seed      integer: makes the noise, talker choice and template choice
%             reproducible ([] = use MATLAB's global random stream)
%   Template  which excitation template to use (1..nTemplates; [] = random)
%   Level     vowel RMS level in dBFS (default -20)
%   PadMs     [before after] silence in ms (default [50 50])
%   SibDur    override the sibilant duration in seconds ([] = talker's)
%   Play      play the result (default false)
%
% Outputs:
%   y     column vector, mono, at Fs (44100 Hz)
%   Fs    sample rate
%   info  struct: talker, a, vowel, durations, sibilant peak frequencies,
%         onset/offset sample indices of the sibilant and vowel, template,
%         seed, the words the token was interpolated between, and
%         vowelContext / vowelA (the option as given and the vowel weight
%         actually used).
%
% Examples:
%   [y, Fs] = SynthSibilant(0, "i");   sound(y, Fs)          % "she", random talker
%   [y, Fs] = SynthSibilant(1, "u", "pert6P02"); sound(y, Fs) % "sue", one talker
%   for a = 0:0.1:1, y = SynthSibilant(a, "i", "pert6P02", 'Seed', 1); ... end
%   y = SynthSibilant(0.5, "u", "pert6P02", 'VowelContext', "morph");  % coarticulating vowel
%
% See also BuildSibilantModel, SynthSibilantTalkers.

arguments
    a (1,1) double {mustBeGreaterThanOrEqual(a, 0), mustBeLessThanOrEqual(a, 1)}
    vowel (1,1) string
    talker (1,1) string = "random"
    opts.Model = ""
    opts.Seed = []
    opts.Template = []
    opts.Level (1,1) double = -20
    opts.PadMs (1,2) double {mustBeNonnegative} = [50 50]
    opts.SibDur = []
    opts.VowelContext = 0.5
    opts.Play (1,1) logical = false
end

M  = loadModel(opts.Model);
Fs = M.Fs;

% vowel
vowel = lower(vowel);
switch vowel
    case {"i", "ee", "she", "see"}, vowel = "i";
    case {"u", "oo", "shoe", "sue"}, vowel = "u";
    otherwise
        error("SynthSibilant:badVowel", "vowel must be ""i"" (she/see) or ""u"" (shoe/sue), got ""%s"".", vowel);
end

% vowel context -> weight of the /s/-context vowel filter (av)
vc = opts.VowelContext;
if isstring(vc) || ischar(vc)
    switch lower(string(vc))
        case "morph", av = a;
        case "sh",    av = 0;
        case "mid",   av = 0.5;
        case "s",     av = 1;
        otherwise
            error("SynthSibilant:badVowelContext", ...
                  "VowelContext must be a number in [0,1], ""sh"", ""mid"", ""s"" or ""morph"", got ""%s"".", string(vc));
    end
elseif isnumeric(vc) && isscalar(vc) && vc >= 0 && vc <= 1
    av = double(vc);
else
    error("SynthSibilant:badVowelContext", "VowelContext must be a number in [0,1], ""sh"", ""mid"", ""s"" or ""morph"".");
end

% random stream
if isempty(opts.Seed)
    rs = RandStream.getGlobalStream;
else
    rs = RandStream('mt19937ar', 'Seed', opts.Seed);
end

% talker
if talker == "random"
    ti = randi(rs, numel(M.talkers));
else
    ti = find(M.talkerIds == talker, 1);
    if isempty(ti)
        error("SynthSibilant:unknownTalker", "Talker ""%s"" is not in the model. See SynthSibilantTalkers.", talker);
    end
end
T = M.talkers(ti);
jsh = find(M.vowelOf == vowel & M.classOf == "sh", 1);
js  = find(M.vowelOf == vowel & M.classOf == "s",  1);
Wsh = T.words(jsh);
Ws  = T.words(js);

%% ---------------------------------------------------------------- sibilant
if isempty(opts.SibDur)
    sibDur = exp((1 - a) * log(Wsh.sibDurS) + a * log(Ws.sibDurS));
else
    sibDur = opts.SibDur;
end
sibLevelDb = (1 - a) * Wsh.sibLevelDb + a * Ws.sibLevelDb;
sibEnvDb   = (1 - a) * Wsh.sibEnvDb   + a * Ws.sibEnvDb;

u = log2(M.logGridHz);
K = M.nSlices;
specDb = zeros(K, numel(u));
peakHz = zeros(1, K);
for k = 1:K
    [specDb(k, :), peakHz(k)] = morphSpectrum(Wsh.sibSpecDb(k, :), Ws.sibSpecDb(k, :), ...
                                              Wsh.sibPeakHz(k), Ws.sibPeakHz(k), a, M.logGridHz);
end

sib = shapedNoise(round(sibDur * Fs), specDb, u, Fs, rs);
sib = sib .* dbContour(sibEnvDb, numel(sib));

%% ------------------------------------------------------------------- vowel
tv = T.templates([T.templates.vowel] == vowel);
if isempty(opts.Template)
    tmpl = randi(rs, numel(tv.residual));
else
    tmpl = opts.Template;
    if tmpl < 1 || tmpl > numel(tv.residual)
        error("SynthSibilant:badTemplate", "Template must be in 1..%d.", numel(tv.residual));
    end
end
e = double(tv.residual{tmpl}(:));

lsf   = (1 - av) * Wsh.vowLsf   + av * Ws.vowLsf;       % frames x order (av = a only if VowelContext = "morph")
rmsDb = (1 - av) * Wsh.vowRmsDb + av * Ws.vowRmsDb;
vow = lpcSynth(e, lsf, M);
vow = imposeContour(vow, rmsDb, round(0.025 * Fs));

%% ------------------------------------------------------------- assemble
vow = vow / rms(vow) * 10^(opts.Level / 20);
sib = sib / rms(sib) * 10^((opts.Level + sibLevelDb) / 20);

xfade = round(0.010 * Fs);                              % 10 ms sibilant -> vowel overlap
sib(end-xfade+1:end) = sib(end-xfade+1:end) .* cosRamp(xfade, -1);
vow(1:xfade)         = vow(1:xfade)         .* cosRamp(xfade, +1);
sib(1:xfade)         = sib(1:xfade)         .* cosRamp(xfade, +1);
vow(end-xfade+1:end) = vow(end-xfade+1:end) .* cosRamp(xfade, -1);

pad = round(opts.PadMs / 1000 * Fs);
sibOn  = pad(1) + 1;
vowOn  = sibOn + numel(sib) - xfade;
n = vowOn + numel(vow) - 1 + pad(2);
y = zeros(n, 1);
y(sibOn:sibOn+numel(sib)-1) = sib;
y(vowOn:vowOn+numel(vow)-1) = y(vowOn:vowOn+numel(vow)-1) + vow;

scaledBy = 1;
if max(abs(y)) > 0.99
    scaledBy = 0.99 / max(abs(y));
    y = y * scaledBy;
end

%% ---------------------------------------------------------------- info
info = struct();
info.talker     = T.id;
info.a          = a;
info.vowel      = vowel;
info.words      = [Wsh.token Ws.token];
info.Fs         = Fs;
info.sibDurS    = numel(sib) / Fs;
info.vowDurS    = numel(vow) / Fs;
info.sibPeakHz  = peakHz;                               % per slice, begin -> end
info.sibLevelDb = sibLevelDb;
info.sibOnset   = sibOn;
info.vowOnset   = vowOn;
info.vowOffset  = vowOn + numel(vow) - 1;
info.vowelContext = opts.VowelContext;
info.vowelA     = av;                                   % weight of the /s/-context vowel filter used
info.template   = tmpl;
info.templateF0Hz = tv.f0Hz(tmpl);
info.seed       = opts.Seed;
info.scaledBy   = scaledBy;

if opts.Play
    sound(y, Fs);
end
end

%% ========================================================================
function M = loadModel(src)
persistent cache cachePath
if isstruct(src)
    M = src; return
end
if src == ""
    src = fullfile(fileparts(mfilename('fullpath')), "sibilant_model.mat");
end
if isempty(cache) || cachePath ~= string(src)
    if ~isfile(src)
        error("SynthSibilant:noModel", ...
            "Model file not found: %s\nRun BuildSibilantModel first (needs the raw recordings).", src);
    end
    S = load(src, 'model');
    cache = S.model; cachePath = string(src);
end
M = cache;
end

%% ------------------------------------------------------------------------
function [La, peakHz] = morphSpectrum(Lsh, Ls, pSh, pS, a, fHz)
% Landmark-aligned morph between two dB spectra sampled on the grid fHz.
% The frequency axis is warped piecewise-linearly in MEL (anchors: grid
% ends and the landmark), so as a goes 0 -> 1 the landmark moves in equal
% mel steps between the /sh/ and /s/ positions.
m   = hz2mel(fHz);
mSh = hz2mel(pSh); mS = hz2mel(pS);
ma  = (1 - a) * mSh + a * mS;                          % intermediate landmark (mel)
m0 = m(1); mN = m(end);
wSh = interp1([m0 ma mN], [m0 mSh mN], m);             % intermediate axis -> /sh/ axis
wS  = interp1([m0 ma mN], [m0 mS  mN], m);             % intermediate axis -> /s/ axis
La = (1 - a) * interp1(m, Lsh, wSh, 'linear', 'extrap') + a * interp1(m, Ls, wS, 'linear', 'extrap');
peakHz = mel2hz(ma);
end

function m = hz2mel(f)
m = 2595 * log10(1 + f / 700);                         % O'Shaughnessy (1987) mel scale
end

function f = mel2hz(m)
f = 700 * (10 .^ (m / 2595) - 1);
end

%% ------------------------------------------------------------------------
function y = shapedNoise(N, specDb, u, Fs, rs)
% STFT-domain shaping of white noise by a time-varying envelope: specDb(k,:)
% holds the envelope (dB) at normalised time (k-0.5)/K; frames interpolate
% between slices.
nfft = 1024; hop = nfft / 4;
win = sqrt(hann(nfft, 'periodic'));
K = size(specDb, 1); tauK = ((1:K) - 0.5) / K;
fb = (0:nfft/2)' * Fs / nfft;
ub = min(max(log2(fb), u(1)), u(end));                 % clamp to the grid (DC -> first bin)
x = randn(rs, N + 2 * nfft, 1);
y = zeros(size(x));
for head = 1:hop:numel(x) - nfft + 1
    tau = (head + nfft/2 - nfft) / N;                  % frame centre in sibilant time
    tau = min(max(tau, tauK(1)), tauK(end));
    Ldb = interp1(tauK, specDb, tau, 'linear');
    H = 10 .^ (interp1(u, Ldb, ub, 'linear') / 20);
    H = [H; flipud(H(2:end-1))];
    frame = x(head:head+nfft-1) .* win;
    y(head:head+nfft-1) = y(head:head+nfft-1) + real(ifft(fft(frame) .* H)) .* win;
end
y = y(nfft + (1:N));
end

%% ------------------------------------------------------------------------
function y = lpcSynth(e, lsf, M)
% Time-varying all-pole synthesis: LSF trajectory over normalised time,
% coefficients updated every lpcHop samples, then de-emphasis.
n = numel(e); y = zeros(n, 1);
nF = size(lsf, 1); tauF = ((1:nF) - 0.5) / nF;
zi = zeros(M.lpcOrder, 1);
for head = 1:M.lpcHop:n
    tail = min(n, head + M.lpcHop - 1);
    tau = min(max(((head + tail) / 2) / n, tauF(1)), tauF(end));
    l = interp1(tauF, lsf, tau, 'linear');
    acoef = lsf2poly(l);
    [y(head:tail), zi] = filter(1, acoef, e(head:tail), zi);
end
y = filter(1, [1 -M.preEmph], y);
end

%% ------------------------------------------------------------------------
function y = imposeContour(x, targetDb, win)
% Rescale x so its RMS contour (dB re. overall RMS, measured in win-sample
% windows at the frame centres) follows targetDb; gains smoothed and clamped.
n = numel(x); nF = numel(targetDb); have = zeros(1, nF);
for m = 1:nF
    c = (m - 0.5) / nF * n;
    head = max(1, round(c - win/2)); tail = min(n, head + win - 1); head = tail - win + 1;
    have(m) = 20 * log10(max(rms(x(head:tail)), eps) / rms(x));
end
gDb = targetDb - have;
gDb = movmean(gDb, 3);
gDb = min(max(gDb, -15), 15);
y = x .* dbContour(gDb, n);
end

function g = dbContour(cDb, n)
% Per-sample linear gain from a dB contour sampled at frame centres.
nF = numel(cDb); tauF = ((1:nF) - 0.5) / nF;
tau = ((1:n)' - 0.5) / n;
g = 10 .^ (interp1(tauF, cDb(:), tau, 'pchip', 'extrap') / 20);
end

function w = cosRamp(n, dir)
% Raised-cosine ramp of n samples: dir = +1 fade in, -1 fade out.
w = 0.5 - 0.5 * cos(pi * (0:n-1)' / max(n - 1, 1));
if dir < 0, w = flipud(w); end
end
