# CLAUDE.md — agent context for sibilant_perception

MATLAB two-alternative forced-choice perception experiment ("did you hear
she or see?") on a sibilant continuum from /ʃ/ (`a = 0`) to /s/ (`a = 1`),
plus the data-driven synthesizer (`synth/`) that makes its she / see /
shoe / sue tokens from the recordings of the `sibilant_adaptation` cohort.
Paul Gribble (pgribble@uwo.ca) is the user. `README.md` and `methods.md`
document the current state for humans; this file is the operational brief:
decisions with their dates and reasons, gotchas, how to work here. Git:
https://github.com/paulgribble/sibilant_perception (renamed from sibilant_synth
on 2026-10-02, and from synth_sibilant on 2026-09-16).

## Layout (2026-10-02)

Experiment functions at the root, synthesis in `synth/`: Paul wanted the
perception experiment to "take center stage" and the synthesizer treated
as its helper. `synth/` rather than a top-level `lib/` because the
synthesizer already has a `lib/` of measurement helpers (now
`synth/lib/`). Not a MATLAB package (`+synth`): that would change every
call. The experiment functions `addpath(fullfile(here, "synth"))`
themselves; `synth/` files locate the `.mat` and `lib/` next to
themselves, so nothing there changed. `stimuli/` (experiment input) and
`data` (output) sit at the root; `synth/test_output/` with its scripts.

```
RunPerceptionExperiment.m  RunPsiExperiment.m  PsiMethod.m  PlotPsiSession.m
PreparePerceptionStimuli.m  FitPsychometric.m
data -> ~/Dropbox/data/sibilant_perception/data   stimuli/
synth/  SynthSibilant.m SynthSibilantTalkers.m WriteSibilantContinuum.m
        BuildSibilantModel.m sibilant_model.mat TestSynthSibilant.m
        ValidateSynthSibilant.m lib/ test_output/
papers/  README.md  methods.md  CLAUDE.md
```

## Mental model

```
raw WAVs + scored boundaries  --BuildSibilantModel-->  synth/sibilant_model.mat
sibilant_model.mat + (a, vowel, talker)  --SynthSibilant-->  y, Fs, info
WriteSibilantContinuum / PreparePerceptionStimuli  -->  stimuli/*.wav
stimuli + listener  --RunPerceptionExperiment | RunPsiExperiment-->  data/*.tsv
data/*.tsv  --FitPsychometric | PlotPsiSession-->  boundary, slope, figures
```

- `SynthSibilant(a, vowel, talker, Name, Value)` — the synthesizer. `vowel`
  "i"/"u" (also ee/oo/she/see/shoe/sue), `talker` "random" or an id (72,
  `SynthSibilantTalkers()`). Options `VowelContext` (weight in [0,1]
  between the /ʃ/- and /s/-context vowel, default 0.5; aliases
  "sh"/"mid"/"s"; "morph" = follows `a`), `Seed`, `Template` (1..2), `Level`
  (vowel RMS dBFS, −20), `PadMs`, `SibDur`, `Play`, `Model`. The model is
  loaded once into a `persistent` cache keyed by path.
- `BuildSibilantModel()` — rebuilds the `.mat` (~40 s with parfor). Needed
  only if the analysis changes or new participants arrive.
- `WriteSibilantContinuum(outDir, ...)` — WAV set + `manifest.tsv` (incl.
  `vowel_context`); passes `VowelContext` through; `Template` defaults to 1
  (Paul, 2026-09-17) so a continuum's vowel is identical end to end,
  excitation included. Paul writes to `stimuli/` (gitignored; rewrite it
  after any change to the synthesis).
- `TestSynthSibilant()` — 3 talkers, figures + WAVs → `synth/test_output/`.
- `ValidateSynthSibilant()` — all 72 talkers, whole-spectrum stats →
  `synth/test_output/validation_all.{tsv,png}`; ~3 min.
- The 2AFC experiment and its analysis (2026-09-17; at the root since
  2026-10-02, no `addpath` needed when run from there).
  - `RunPerceptionExperiment(participant, ...)`: uifigure GUI, two buttons
    (she/see, shoe/sue, or "she / shoe"/"see / sue" when vowels are mixed)
    + keys F/J (`Keys`, `ShSide` for counterbalancing). Options `A`,
    `Reps`, `Practice`, `Vowels`, `Talkers` (default "pert4P17", Paul's
    choice 2026-09-17), `ItiS`, `BreakEvery`, `Seed`, `StimDir`, `DataDir`,
    `Regenerate`, `WindowState`, `Simulate` ([pse sigma lapse] logistic
    listener, no GUI/audio). Blocked randomisation: each rep is one
    shuffled block of all talker × vowel × a. Responses accepted only after
    token offset; each trial appended to `data/<id>_<stamp>.tsv` at once
    (+ `.json` of settings); Esc/close = early exit.
  - `Reps` may be a vector (2026-09-30), one count per level of `A` in the
    order typed: `max(Reps)` blocks, a level with fewer reps sits in that
    many blocks, evenly spaced from a random start; a scalar gives the same
    order per `Seed` as before; the `.json` records `reps` per sorted
    level. Suggested design (2026-10-01, in the doc header): 21 levels,
    `A = [0 0.2 0.25 0.3 0.35 0.4:0.02:0.6 0.65 0.7 0.75 0.8 1]`,
    `Reps = [6 3 5 9 10 7 5 6 6 7 8 7 6 6 5 7 10 9 5 3 6]` = 136 trials,
    Paul's ceiling. Paul's prior (2026-10-01): pse in 0.4–0.6, 25–75 %
    width 0.1–0.4; he wanted a dense, heavily repeated centre for the
    slope. Found by an exchange search on the expected Fisher information
    (μ, log σ, symmetric lapse; mean of log SD(μ) + log SD(log σ) over a
    5 × 5 prior grid), then 400-session checks with FitPsychometric: the
    asymptotic optimum is bimodal (mass at ≈ 0.35 and 0.65, a centre
    cluster, endpoints), but in finite samples a 0.05 grid loses 40–60 %
    on the slope for steep functions (2–3 levels on the transition), so
    the hybrid keeps the 0.02 centre. Pilot1 (2026-09-30) had pse 0.59,
    σ 0.042. Earlier suggestions: 17 levels 0.4:0.025:0.6, 110 trials
    (2026-09-30); 19 levels 0.4:0.02:0.6, reps peaking 14 at 0.5, 136
    trials (2026-10-01 morning): equal at pse 0.5, 15–20 % worse at 0.4
    or 0.6. Scratch scripts for the search are not kept; the method is
    above. Enough for the planned 0.075 pre/post shift at n = 20–30,
    where between-subject variance dominates.
  - `Practice` (default 3; Paul, 2026-09-17): a practice block of the
    endpoint tokens a = 0 and a = 1 per talker × vowel whatever `A` is, no
    feedback, rows tagged `phase = "practice"`, `trial` counted within
    phase, `block` 0; FitPsychometric keeps only `phase == "main"`; the
    main order for a given `Seed` does not depend on `Practice`.
  - `RunPsiExperiment(participant, ...)` (2026-10-01, Paul asked for a
    Kontsevich & Tyler 1999 version): same GUI, practice block and data
    format, but each trial's level is chosen by `PsiMethod` (handle class:
    posterior on a grid μ 0:0.005:1 × 41 log-spaced σ in [0.005 0.5] ×
    lapse [0 .01 .02 .04 .08], uniform prior; next level = minimum
    expected entropy of the (μ, log σ) marginal, Prins 2013; `next` takes
    4 ms). Options `Levels` (0:0.01:1 since 2026-10-01 at Paul's request,
    was 0:0.02:1; all synthesised up front, pert4P17 i/u are in `stimuli/`),
    `Opening` ([0 0.2 0.4 0.5 0.6 0.8 1] shuffled per function before Ψ
    chooses; Paul, 2026-10-01, so every listener first hears the whole
    continuum rather than the deterministic 0.5-then-outward walk of the
    greedy rule, which could bias them; was 0.3:0.05:0.7 earlier that day,
    which only bracketed the middle; 80 simulated sessions at pse 0.55,
    σ 0.04: boundary RMSE 0.012 vs 0.010 without an opening, SD(log σ)
    0.235 either way),
    `MaxTrials` (100 per talker × vowel, opening included), `StopSd`
    ([sdMu sdLogSigma], default [0.02 0.3] since 2026-10-01 at Paul's
    request, was []; [] = none; checked from `MinTrials` 30),
    `SigmaRange`, `Lapse`,
    `Function`; several talker × vowel functions are interleaved in rounds.
    Rows carry `pick` (opening/psi) and `mu_hat sigma_hat mu_sd logsigma_sd
    lapse_hat` (no `block`); the
    `.json` has `estimates`. The GUI code is a copy of
    RunPerceptionExperiment's (its nested-callback design made a shared
    helper a bigger refactor than the duplication); change both together.
    Simulation (2026-10-01, scratch not kept): pse {0.45 0.55} × σ
    {0.02 0.04 0.07} × lapse {0 0.03}, 300 sessions × 200 trials each,
    posterior means recorded per trial, FitPsychometric MLE at 50:25:150,
    and the 136-trial constant design on the same listeners. Per-session
    pse RMSE 0.007–0.029 (N 50), 0.005–0.021 (100), 0.004–0.016 (150);
    SD(log σ) 0.32–0.41, 0.22–0.26, 0.18–0.21; constant 136: 0.008–0.019
    and 0.26–0.80. Posterior SDs match the RMSE within ~10 % (slightly
    conservative at N 50), so they are a valid stop rule: [0.015 0.25]
    with MaxTrials 150 → median 103–111 trials at σ ≤ 0.04, 145–168 at
    σ 0.07 (11–29 % hit the cap); [0.02 0.30] → 75–104, none capped.
    Trials never land at a ≤ 0.1 or ≥ 0.9, so lapses are constrained
    only weakly; σ is biased −10 % at lapse 0 (prior mean lapse 0.03),
    the MLE equally. Simulated with 0.02 levels; a 0.01 check (3 cells,
    150 sessions) gave the same precision. Defaults: `StopSd` [0.02 0.3]
    with `MaxTrials` 100 (≤ ~4 min); `StopSd` [0.015 0.25] with
    `MaxTrials` 150 when the slope matters most.
    Headless GUI test with injected keys/clicks passed (normal end);
    Esc/close paths not run. `PlotPsiSession(file)` (Paul, 2026-10-01):
    2 × 2 figure per session, levels + running boundary, running
    `Measure` (width default / sigma / slope), posterior SD of boundary
    and of `Measure` (delta method, estimate × SD of log σ) vs trials on
    log axes, StopSd lines; saves `<file>_psi.png` (`_psi_<Measure>.png`
    for sigma/slope).
  - `PreparePerceptionStimuli(stimDir, talkers, vowels, A)`: finds
    `<talker>_<vowel>_a<a>.wav` by name, synthesises missing ones in a
    batch with the WriteSibilantContinuum defaults (seed hashed from the
    file name) and appends them to `manifest.tsv`; never synthesises
    during trials.
  - `FitPsychometric(file | table, ...)`: MLE of
    γ + (1−γ−λ)·F((a−μ)/σ), F logistic (default) or normal, `Lapse`
    "symmetric" (default, ≤ `LapseMax` 0.1) / "free" / "none",
    `fminsearch` from a grid (no toolboxes), per `By` group (default
    vowel), parametric bootstrap CIs + deviance p, writes
    `<file>_fit.{tsv,png}`.
- `synth/lib/` — measurement helpers: `measureMidSpectrum` (three 50 ms
  multitaper windows at mid-sibilant, mirrors the experiment's "m" point),
  `spectrumFeatureGrid` / `spectrumFeatures` (1/12-oct, 500 Hz–16 kHz,
  level-normalised), `loadRealSpectra` (reads the experiment's per-trial
  `*_spectra.tsv`), `fitSpectrumLda` / `applySpectrumLda`. The roster's
  `sex` column is read only for the `EstimateFormants` preset in
  Test/Validate (its option is still spelled `'gender'` inside the
  experiment lib; leave that, it is a preset name). The synthesis never
  reads it; `talkers(i).sex` is a label copied from the roster at build
  time, stale until the next rebuild.

## Data (all external to this folder)

- Raw audio: `/Users/plg/Library/CloudStorage/Dropbox/data/sibilant_adaptation/raw_data/<group>/<pid>/*.wav`
  (folder renamed from sibilant_experiment on 2026-10-02),
  stereo, **ch1 = mic** (used), ch2 = feedback (ignored). 44.1 kHz for the
  pert cohorts, 48 kHz for ryan (excluded anyway: no practice block, hence
  no see/sue).
- Experiment repo: `/Users/plg/github/sibilant_adaptation` (renamed from
  sibilant_experiment on 2026-10-02; the defaults in Build/Test/Validate
  follow) — read its
  `README.md`, `code/analysis/README.md`, `code/analysis/CLAUDE.md` for the
  data conventions. Used here: `participants.tsv` (roster; its `sex`
  column, renamed from `gender` 2026-09-18 at Paul's call since sex is the
  acoustic variable and gender is identity, is Paul's by-ear rating of
  every voice from 2026-09-18, not self-report; it was a `male` placeholder
  before; 29 of the 72 model talkers male, 43 female; pert4P17 is male;
  future participants will be asked both), `scored_data/<pid>_scored.tsv`
  (sib_start, sib_end = vowel onset, vow_end, **in samples**, NaN =
  skipped), `extracted_data/all_extracted.tsv` (per-trial scalars incl.
  vow_f1/vow_f2, sib_cog; re-extracted 2026-09-18 with the by-ear roster),
  `extracted_data/participants/<pid>_spectra.tsv` (gitignored there but
  present locally; per-trial mid-sibilant spectra on a 40 Hz grid, dB;
  rows: point b/m/e × channel mic/fb), `code/analysis/lib/EstimateFormants.m`
  (formant tracker, used only in validation via addpath).
- WAV filename parsed from the END, split on `_`: `end-5` = token,
  `end-4` = phase letter (P practice / B baseline / E adaptation / A
  after-effect). **Only P and B trials are used** — they are unshifted.
  Per talker: 30 she, 30 shoe (5 practice + 25 baseline each) and only
  **5 see, 5 sue** (practice only). Every tabular file is TSV: MATLAB
  `readtable(..., 'FileType','text','Delimiter','\t')`.

## Design decisions (don't undo without a reason)

- **Data-driven, not a synthesizer from scratch** — Paul's explicit ask.
  Endpoints must sound drawn from the recorded distribution; vowels must be
  realistic and carry the she-vs-see coarticulation; per-talker synthesis.
- **Sibilant = morph, not cross-fade.** Whole time-varying spectra (5 slices,
  1/48-oct log grid) are warped piecewise-linearly **in mel** so the two
  landmarks coincide at `mel⁻¹((1−a)·mel(f_ʃ) + a·mel(f_s))`, then levels
  are interpolated. A plain dB mix gives bimodal spectra at a ≈ 0.5.
  **Equal steps in `a` = equal mel steps of the landmark** (Paul's request,
  2026-09-16; it was log2 f before, whose mel size grows with frequency, so
  the /ʃ/ end was finer and the /s/ end coarser in mel). Mel =
  O'Shaughnessy 2595·log10(1+f/700), `hz2mel`/`mel2hz` local to
  SynthSibilant.
- **Landmark = power-weighted log-f centroid of the region within 6 dB of
  the in-band max** (bands /ʃ/ 1.8–5 kHz, /s/ 3–10 kHz). A plain argmax
  jumped between 3.0 and 3.9 kHz across slices on plateau-shaped /ʃ/ spectra.
- **Sibilant spectra averaged across trials in linear power** (then dB), σ =
  1/24-oct Gaussian smoothing. dB averaging + heavier smoothing biased the
  rendered spectrum upward in frequency.
- **Vowel filter averaged in the LSF domain**, order 40 at 44.1 kHz,
  pre-emphasis 0.97, 30 ms windows, 40 normalised-time frames. Averaging
  LPC envelopes and refitting broadened formant bandwidths ~20 % (pert8P15
  she: F2 BW 322 Hz per trial vs 385 refit vs 373 mean-LSF). The
  a-interpolation of LSFs between she- and see-context filters is stable
  because convex combinations of sorted LSF vectors stay sorted.
- **Vowel fixed across the continuum by default** (`VowelContext = 0.5`,
  Paul's decision 2026-09-17 after reviewing Lane et al. 2007 / Shiller et
  al. 2009, who concatenated one natural vowel to every step): the listener
  gets a single cue, the sibilant. The a-following coarticulation is kept as
  `VowelContext = "morph"`. Why 0.5: neutral (biases the boundary toward
  neither category), the she/see filter difference is small anyway (mid F2
  tens of Hz, onset F2 ~100 Hz before /u/, ~15 Hz before /i/), and 0.5
  keeps the variance near the 30-trial /ʃ/ estimate (5 see/sue trials make
  the pure /s/-context vowel noisy). The sibilant is unaffected by the
  option (checked bit-identical). Test and Validate synthesise the endpoints
  with "morph" for their vowel-formant check, since a fixed vowel cannot be
  compared with real she vs see.
- **Excitation = the talker's own LPC residual** (two templates per talker ×
  vowel, from the she/shoe trials nearest the median vowel duration), so
  F0/voice quality are real. Consequence: vowel duration and F0 never vary
  with `a`; only the filter and RMS contour can, and only with
  `VowelContext = "morph"`. Templates come from the /ʃ/ words only (30
  trials to choose from vs 5) and are used for all `a`, so there is no
  excitation discontinuity along the continuum.
- Sibilant level is relative to the vowel (data-driven, interpolated in
  dB); vowel RMS is set by `Level`. Sibilant duration interpolates
  log-linearly. 10 ms cross-fade at the sibilant→vowel join; **120 ms
  raised-cosine ramp at the vowel offset** (10 ms → 40 ms on 2026-09-30,
  → 120 ms on 2026-10-01, both because Paul heard a click or "thunk" at
  the end of tokens). Why: the scored vow_end is still voiced, median
  −17 dB re mid-vowel, max −8; 10 of the 288 residual templates carry an
  end-of-phonation click 2–17 ms before the end; and the mean RMS contour
  holds the level until the end, whereas the real pert4P17 she offset is
  15–19 dB down at vow_end and decays another 30–40 ms into noise (~90 ms
  tail). With 40 ms the synthetic tail had no click, DC or low-frequency
  excess, just a 40 dB fall in 15 ms: a gated offset. Paul compared 40,
  80, 120 ms cosine and a 100 ms exponential fade on pert4P17 endpoints
  and chose 120 ms. Templates are ≥ 162 ms, so the ramp never covers a
  whole vowel. The onset and join ramps stay 10 ms.)
- Outlier rejection (duration, level; > 3 robust SD) only for words with
  ≥ 10 trials — MAD on 5 see/sue trials threw out good ones. Clipped trials
  (> 0.99), sibilants < 60 ms, vowels < 80 ms are dropped. pert6P08 is
  excluded (0 usable see trials) → 72 talkers.
- **Validation uses the whole spectrum, not COG.** Paul: "using cog to
  characterize sibilants may be suboptimal. is there a way to use the
  entire spectrum instead?" So: endpoint RMS z against the talker's real
  trial cloud (leave-one-out real trials for scale), position on the
  talker's own /ʃ/→/s/ spectral axis, and a pooled shrinkage Fisher
  discriminant. Don't reintroduce COG as the headline check.

## Validation state

72 talkers × 2 vowels. Sibilant numbers from 2026-09-16 (after the mel
morph; unchanged by the fixed-vowel default 2026-09-17, the `gender` →
`sex` rename 2026-09-18 and the offset ramps of 2026-09-30 and
2026-10-01), vowel numbers from 2026-10-01.

Endpoint RMS z 0.53 (/ʃ/) / 0.63 (/s/) vs real trials' 0.69 / 0.94 —
synthetic endpoints sit inside every talker's cloud. Talker-own-axis
position −0.02 → 0.97, monotonic in 100 % of cells, steps 0.08–0.12 per 0.1
in a. Pooled discriminant 0.04 → 1.02, mean course mildly S-shaped;
individual curves wobble a few hundredths on that axis (43 % strictly
monotonic; not noise — averaging 8 seeds didn't fix it — but it's the
population axis, not the talker's). Mid-vowel F1/F2 errors median −4/−5 Hz
after /ʃ/, −6/−4 Hz after /s/ (MAD ≤ 31), F2 measurable in 91 % / 85 % of
synthetic tokens; reference and synthesis use the same by-ear `sex`
presets since `all_extracted.tsv` was re-extracted on 2026-09-18 (before
that, with all-male presets capping F2 at 2600 Hz, F2 was measurable in
only ~70 % and the errors were −7/+16, −8/+7 Hz: the preset, not the
synthesis). Paul listened on 2026-09-30 (pilots 1–3) and again on
2026-10-01 and heard the offset thunk both times (ramp 10 → 40 → 120 ms);
the agent cannot listen.
`synth/test_output/wav/` holds 66 examples (local only; `TestSynthSibilant`
regenerates them).

## Working here

- Run MATLAB headless: `/Applications/MATLAB_R2026a.app/bin/matlab -batch "..."`.
  Multi-line code inline breaks on shell quoting — write a script to the
  scratchpad and `-batch "run('/path/script.m')"`. Needs Signal Processing
  Toolbox (`pmtm`, `lpc`, `poly2lsf`, `lsf2poly`); Parallel Computing
  optional (build uses parfor).
- Gotchas hit: `interp1` on a single spectrum returns a row that transposes
  to a column (features went to all-zeros — fixed by a column query in
  `spectrumFeatures`); pmtm grids start at DC, drop f = 0 before `log2`;
  the 1/48-oct grid's last point falls just short of Nyquist, clamp FFT-bin
  queries to the grid; struct arrays with differing fields need cell
  collection then `[c{:}]`; `x(:)(w)`-style indexing of a literal array is
  not valid MATLAB.
- `ValidateSynthSibilant` / `TestSynthSibilant` error out if any requested
  talker lacks `extracted_data/participants/<pid>_spectra.tsv` in the
  experiment repo (all 72 were present on 2026-09-17). Regenerate with
  `extract_spectra("<pid>")` there, or pass `'Talkers'` with the subset
  that has spectra; a 70-talker subset reproduced the 72-talker statistics.
- `synth/test_output/` is regenerated by the test/validate scripts and
  `stimuli/` by `WriteSibilantContinuum` (topped up by
  `PreparePerceptionStimuli`); both safe to delete. Both are gitignored
  (along with `data` — participant data, NOT regenerable; on
  Paul's Mac it is a symlink (2026-10-02) to
  `~/Dropbox/data/sibilant_perception/data`, so the
  ignore pattern has no trailing slash, which would match only a real
  directory — `*.asv`, `*.autosave`, `slprj/`, `.DS_Store`), so a fresh
  clone has none of it. `sibilant_model.mat` IS tracked.
- Testing the experiment GUI headless (works under `-batch` on this Mac):
  put a silent stand-in `audioplayer` classdef (constructor, `play`,
  `stop`) first on the path so nothing plays, start a `timer` whose
  callback finds the uifigure by name ("Listening experiment") and calls
  `fig.WindowKeyPressFcn(fig, struct('Key','f'))` or a button's
  `ButtonPushedFcn`; `exportapp(fig, file)` screenshots it. Gotcha
  (2026-09-17): an `onCleanup(@() delete(fig))` inside a function whose
  nested functions are the figure's callbacks never fires (the callbacks
  keep that workspace alive), and with `CloseRequestFcn` = abort the
  leftover window could not be closed. Now `delete(fig)` is explicit
  (try/catch around `runTrials`), and a 2nd close request deletes a window
  orphaned by ctrl-C. Verified for normal end and Esc; the close-box and
  error paths were not run.
  Stale-stimulus trap: the experiment reuses whatever WAVs are in
  `stimuli/`; after a synthesis change pass `'Regenerate', true` or rewrite
  the set. Simulated recovery (pse 0.45, σ 0.06, 11 levels): pse unbiased,
  SD 0.024 @ 10 reps; with 3 % lapses `Lapse="none"` inflates σ ~50 %,
  "symmetric" does not — keep it the default.
- `synth/lib/` is not on the MATLAB path by itself: `TestSynthSibilant`
  and `ValidateSynthSibilant` `addpath` it (and the experiment repo's
  `code/analysis/lib`) at the top. `SynthSibilant`, `BuildSibilantModel`
  and `WriteSibilantContinuum` use only local functions. The experiment
  functions at the root `addpath` `synth/` themselves; using the
  synthesizer directly needs `addpath synth`.
- Model struct fields: `Fs, tokens, vowelOf, classOf, nSlices, logGridHz,
  lpcOrder, preEmph, lpcHop, talkerIds, talkers(i).words(j).{sibSpecDb,
  sibPeakHz, sibEnvDb, sibDurS, sibLevelDb, vowLsf, vowRmsDb, vowDurS,
  vowF0Hz, vowSpecDb, n, included}, talkers(i).templates(v).{residual{},
  vowDurS, f0Hz, source}`. Changing the analysis = rebuild + re-validate.

## Documentation rules (Paul's, 2026-09-16 and 2026-09-30)

- **Review all documentation after every code change and again at every
  commit.** That means every `.m` doc header (the `%` block under the
  `function` line, in all top-level files, `synth/` and `synth/lib/`),
  `README.md`, `methods.md` and this `CLAUDE.md`.
  Check for accuracy and currency: algorithm descriptions, option lists,
  defaults, file tables, output fields, `.gitignore` contents, model fields,
  validation numbers (re-run `TestSynthSibilant` / `ValidateSynthSibilant`
  if the synthesis or analysis changed) and the design-decision entries.
  Fix what is stale in the same commit as the code change.
- **`README.md`, `methods.md` and the inline docs describe the current state
  of the code only.** No change history, no "before X it was Y", no dates
  of changes: that record lives in git and in this file. When updating
  them, replace the old statement rather than appending the new one. This
  file is the one place for decisions, their dates and the reasons behind
  them.
- Keep all three concise: say each thing once, in the place a reader will
  look for it (what a function does and its options in its header; how the
  system works and how to use it in `README.md`; the paper-ready method and
  the comparison with Lane et al. in `methods.md`).
- **Prefer concise descriptions to verbose text; use fewer words when you
  can** (Paul, 2026-10-01). A short, precise statement beats a long one.

## Open ideas (not done, ask Paul first)

- Vowel duration/F0 varying with `a` would need pitch-synchronous
  time-scaling of the residual or a synthetic glottal source.
- A second landmark (e.g. the lower −6 dB edge) if the single-landmark morph
  proves perceptually uneven; the ~11 kHz /s/ peak currently fades in by
  level rather than gliding.
- Include pert0 sham adaptation trials (also unshifted) to thicken the
  she/shoe estimates; nothing can thicken see/sue (5 trials each).
- Listening tests to locate the category boundary in `a`: the tooling
  exists (the root functions) and Paul has run pilots on himself
  (2026-09-30, constant stimuli; none yet with `RunPsiExperiment`); a real
  pilot could also compare the fixed vowel with `"morph"`, and a
  Lane-style level-only path with the mel morph.
- Appraisal of Lane et al. 2007 (2026-09-17, `papers/`): their continuum
  interpolates Klatt formant amplitudes at fixed frequencies, so
  intermediate spectra are broad/bimodal; on our data the /ʃ/ resonance is
  not present as a peak in /s/ (27 % of cells), so in software it collapses
  to the dB cross-fade already rejected. Kept the mel morph; borrowed the
  fixed vowel; step re-spacing by pilot still to do.
