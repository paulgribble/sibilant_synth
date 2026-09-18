# CLAUDE.md — agent context for sibilant_synth

MATLAB synthesizer for she / see / shoe / sue tokens whose sibilant lies on a
continuum from /ʃ/ (`a = 0`) to /s/ (`a = 1`), built from the recordings of
the `sibilant_experiment` cohort. Purpose: stimuli for a planned
two-alternative forced-choice perception experiment ("did you hear she or
see?"). Paul Gribble (pgribble@uwo.ca) is the user. `README.md` documents the
current state for humans; this file is the operational brief — decisions,
gotchas, how to work here. Git repository: https://github.com/paulgribble/sibilant_synth (renamed from synth_sibilant on 2026-09-16).

## Mental model

```
raw WAVs + scored boundaries  --BuildSibilantModel-->  sibilant_model.mat
sibilant_model.mat + (a, vowel, talker)  --SynthSibilant-->  y, Fs, info
```

- `SynthSibilant(a, vowel, talker, Name, Value)` — the deliverable.
  `vowel` "i"/"u" (also accepts ee/oo/she/see/shoe/sue), `talker` "random" or
  an id (72 available, `SynthSibilantTalkers()`). Options `VowelContext`
  (fixed weight in [0,1] between /ʃ/- and /s/-context vowel, default 0.5;
  aliases "sh"/"mid"/"s"; or "morph" = follows `a`), `Seed`, `Template`
  (1..2), `Level` (vowel RMS dBFS, −20), `PadMs`, `SibDur`, `Play`, `Model`.
  Model is loaded once into a `persistent` cache keyed by path.
- `BuildSibilantModel()` — rebuilds the `.mat` (~40 s with parfor over
  talkers). Only needed if the analysis changes or new participants arrive.
- `WriteSibilantContinuum(outDir, ...)` — WAV set + `manifest.tsv` (incl.
  `vowel_context`) for the presentation script; passes `VowelContext`
  through; `Template` defaults to 1 there (Paul, 2026-09-17) so a
  continuum's vowel is identical end to end, excitation included. Paul
  writes to `stimuli/` (gitignored, regenerable; rewrite it after any
  change to the synthesis).
- `TestSynthSibilant()` — 3 talkers, detailed figures + WAVs → `test_output/`.
- `ValidateSynthSibilant()` — all 72 talkers, whole-spectrum stats →
  `test_output/validation_all.{tsv,png}`; ~3 min.
- `perception_experiment/` (added 2026-09-17) — the 2AFC identification
  experiment and its analysis; `addpath perception_experiment` to use it.
  `RunPerceptionExperiment(participant, ...)`: uifigure GUI, two buttons
  (she/see, shoe/sue, or "she / shoe"/"see / sue" when vowels are mixed) +
  keys F/J (`Keys`, `ShSide` for counterbalancing); options `A`, `Reps`,
  `Practice` (default 3; added 2026-09-17 at Paul's request: a practice
  block of the endpoint tokens a = 0 and a = 1 per talker × vowel, whatever
  `A` is, no feedback, rows tagged `phase = "practice"`, `trial` counted
  within phase, `block` 0; FitPsychometric keeps only `phase == "main"`;
  the main order for a given `Seed` does not depend on `Practice`),
  `Vowels`, `Talkers` (default "pert4P17", Paul's choice 2026-09-17; it was
  "pert6P02" at first, an arbitrary placeholder), `ItiS`, `BreakEvery`, `Seed`, `StimDir`, `DataDir`,
  `Regenerate`, `WindowState`, `Simulate` ([pse sigma lapse] logistic
  listener, no GUI/audio). Blocked randomisation (each rep = one shuffled
  block of all talker × vowel × a). Responses accepted only after token
  offset; each trial appended to `data/<id>_<stamp>.tsv` immediately
  (+ `.json` of settings); Esc/close = early exit.
  `PreparePerceptionStimuli(stimDir, talkers, vowels, A)`: finds
  `<talker>_<vowel>_a<a>.wav` by name, synthesises missing ones in a batch
  with the WriteSibilantContinuum defaults (seed hashed from the file name)
  and appends them to `manifest.tsv`; never synthesises during trials.
  `FitPsychometric(file | table, ...)`: MLE of
  γ + (1−γ−λ)·F((a−μ)/σ), F logistic (default) or normal, `Lapse`
  "symmetric" (default, ≤ `LapseMax` 0.1) / "free" / "none", `fminsearch`
  from a grid (no toolboxes), per `By` group (default vowel), parametric
  bootstrap CIs + deviance p, writes `<file>_fit.{tsv,png}`.
- `lib/` — shared measurement helpers: `measureMidSpectrum` (three 50 ms
  multitaper windows at mid-sibilant, mirrors the experiment's "m" point),
  `spectrumFeatureGrid` / `spectrumFeatures` (1/12-oct, 500 Hz–16 kHz,
  level-normalised), `loadRealSpectra` (reads the experiment's per-trial
  `*_spectra.tsv`), `fitSpectrumLda` / `applySpectrumLda`. Gender is read
  from the roster only for the `EstimateFormants` preset in Test/Validate —
  the synthesis never reads it; the model's `talkers(i).gender` is a label
  copied from the roster at build time, stale until the next rebuild.

## Data (all external to this folder)

- Raw audio: `/Users/plg/Library/CloudStorage/Dropbox/data/sibilant_experiment/raw_data/<group>/<pid>/*.wav`,
  stereo, **ch1 = mic** (used), ch2 = feedback (ignored). 44.1 kHz for the
  pert cohorts, 48 kHz for ryan (ryan is excluded anyway: no practice block,
  hence no see/sue).
- Experiment repo: `/Users/plg/github/sibilant_experiment` — read its
  `README.md`, `code/analysis/README.md`, `code/analysis/CLAUDE.md` for the
  data conventions. Used here: `participants.tsv` (roster; `gender` was a
  `male` placeholder on every row until 2026-09-18, when Paul started
  rating it by ear with the experiment repo's `code/analysis/rate_gender.m`;
  a provisional guess had 42 of the 72 model talkers female, 30 male, and
  pert4P17 male), `scored_data/<pid>_scored.tsv` (sib_start,
  sib_end = vowel onset, vow_end, **in samples**, NaN = skipped),
  `extracted_data/all_extracted.tsv` (per-trial scalars incl. vow_f1/vow_f2,
  sib_cog), `extracted_data/participants/<pid>_spectra.tsv` (gitignored
  there but present locally; per-trial mid-sibilant spectra on a 40 Hz grid,
  dB; rows: point b/m/e × channel mic/fb), `code/analysis/lib/EstimateFormants.m`
  (formant tracker, used only in validation via addpath).
- WAV filename parsed from the END, split on `_`: `end-5` = token,
  `end-4` = phase letter (P practice / B baseline / E adaptation / A
  after-effect). **Only P and B trials are used** — they are unshifted.
  That gives per talker 30 she, 30 shoe (5 practice + 25 baseline each) and
  only **5 see, 5 sue** (practice only). Every tabular file is TSV: MATLAB
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
  2026-09-16; it was log2 f before — equal octave steps, whose mel size
  grows with frequency, so the /ʃ/ end was finer and the /s/ end coarser in
  mel). Mel = O'Shaughnessy
  2595·log10(1+f/700), `hz2mel`/`mel2hz` local to SynthSibilant.
- **Landmark = power-weighted log-f centroid of the region within 6 dB of
  the in-band max** (bands /ʃ/ 1.8–5 kHz, /s/ 3–10 kHz). A plain argmax
  jumped between 3.0 and 3.9 kHz across slices on plateau-shaped /ʃ/ spectra.
- **Sibilant spectra averaged across trials in linear power** (then dB), σ =
  1/24-oct Gaussian smoothing. dB averaging + heavier smoothing biased the
  rendered spectrum upward in frequency.
- **Vowel filter averaged in the LSF domain**, order 40 at 44.1 kHz,
  pre-emphasis 0.97, 30 ms windows, 40 normalised-time frames. Averaging
  LPC envelopes and refitting broadened formant bandwidths ~20 % (checked on
  pert8P15 she: F2 BW 322 Hz per trial vs 385 refit vs 373 mean-LSF). The
  a-interpolation of LSFs between she- and see-context filters is stable
  because convex combinations of sorted LSF vectors stay sorted.
- **Vowel fixed across the continuum by default** (`VowelContext = 0.5`,
  Paul's decision 2026-09-17 after reviewing Lane et al. 2007 / Shiller et
  al. 2009, who concatenated one natural vowel to every step): the listener
  gets a single cue, the sibilant. The a-following coarticulation is kept as
  `VowelContext = "morph"`. Why 0.5 and not the she- or see-context vowel:
  neutral (biases the boundary toward neither category), the she/see filter
  difference is small anyway (mid F2 tens of Hz, onset F2 ~100 Hz before /u/,
  ~15 Hz before /i/), and 0.5 keeps the variance near the 30-trial /ʃ/
  estimate (5 see/sue trials make the pure /s/-context vowel noisy). The
  sibilant is unaffected by the option (checked bit-identical). Test and
  Validate synthesise the endpoints with "morph" for their vowel-formant
  check, since a fixed vowel cannot be compared with real she vs see.
- **Excitation = the talker's own LPC residual** (two templates per talker ×
  vowel, from the she/shoe trials nearest the median vowel duration), so
  F0/voice quality are real. Consequence: vowel duration and F0 never vary
  with `a`; only the filter and RMS contour can, and only with
  `VowelContext = "morph"`. Templates come from the /ʃ/
  words only (30 trials to choose from vs 5) and are used for all `a`, so
  there is no excitation discontinuity along the continuum.
- Sibilant level is relative to the vowel (data-driven, interpolated in
  dB); vowel RMS is set by `Level`. Sibilant duration interpolates
  log-linearly. 10 ms cross-fade at the sibilant→vowel join.
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

## Validation state (2026-09-16, 72 talkers × 2 vowels, re-run after the mel morph; re-run 2026-09-17 after the fixed-vowel default, all numbers unchanged; re-run 2026-09-18 with per-talker gender formant presets, only the vowel numbers changed)

Endpoint RMS z 0.53 (/ʃ/) / 0.63 (/s/) vs real trials' 0.69 / 0.94 —
synthetic endpoints sit inside every talker's cloud. Talker-own-axis
position −0.02 → 0.97, monotonic in 100 % of cells, steps 0.08–0.12 per 0.1
in a (the switch from log2 to mel changed nothing else here). Pooled discriminant 0.04 → 1.02, mean course mildly S-shaped;
individual curves wobble a few hundredths on that axis (43 % strictly
monotonic; not noise — averaging 8 seeds didn't fix it — but it's the
population axis, not the talker's). Mid-vowel F1/F2 errors median −7/+16 Hz
after /ʃ/, −8/+7 Hz after /s/ (MAD ≤ 39), F2 measurable in 91 % / 85 % of
synthetic tokens. With the all-male presets (F2 capped at 2600 Hz) F2 was
measurable in only ~70 %; with a provisional per-talker guess (since
replaced by Paul's by-ear ratings in the roster's `gender` column) female
/i/ F2 was measurable in 41/42 cells, male /i/ in 24/30 — so the old
failures were largely the preset's F2 cap, not only a tracker limitation.
Caveat: the real reference means (`all_extracted.tsv`) were extracted in
the experiment repo with the all-male roster, so the female talkers' F2
error (+27/+21 Hz; male −4/−19) partly reflects the preset mismatch.
**To do once the roster is fully rated**: re-run the experiment's
extraction, then `ValidateSynthSibilant`, and refresh these vowel numbers.
**Nobody has listened to
the tokens yet** (the agent can't); `test_output/wav/` holds 66 examples
(local only — not in git; run `TestSynthSibilant` to regenerate).

## Working here

- Run MATLAB headless: `/Applications/MATLAB_R2026a.app/bin/matlab -batch "..."`.
  Multi-line code inline breaks on shell quoting — write a script to the
  scratchpad and `-batch "run('/path/script.m')"`. No MATLAB MCP tools in
  this environment. Needs Signal Processing Toolbox (`pmtm`, `lpc`,
  `poly2lsf`, `lsf2poly`); Parallel Computing optional (build uses parfor).
- Gotchas hit: `interp1` on a single spectrum returns a row that transposes
  to a column (features went to all-zeros — fixed by a column query in
  `spectrumFeatures`); pmtm grids start at DC, drop f = 0 before `log2`;
  the 1/48-oct grid's last point falls just short of Nyquist, clamp FFT-bin
  queries to the grid; struct arrays with differing fields need cell
  collection then `[c{:}]`; `x(:)(w)`-style indexing of a literal array is
  not valid MATLAB.
- `ValidateSynthSibilant` / `TestSynthSibilant` error out if any requested
  talker lacks `extracted_data/participants/<pid>_spectra.tsv` in the
  experiment repo (pert6P19 and pert6P20 lacked one at some point; all 72
  were present on 2026-09-17). Regenerate with `extract_spectra("<pid>")`
  there, or pass `'Talkers'` with the subset that has spectra; the 70-talker
  subset reproduced the 72-talker statistics.
- `test_output/` is regenerated by the test/validate scripts and `stimuli/`
  by `WriteSibilantContinuum` (and topped up by `PreparePerceptionStimuli`);
  both safe to delete. Both are gitignored (along with
  `perception_experiment/data/` — participant data, NOT regenerable —
  `*.asv`, `*.autosave`, `slprj/`, `.DS_Store`), so a fresh clone has none
  of it. `sibilant_model.mat` IS tracked.
- Testing the experiment GUI headless (done 2026-09-17, works under
  `-batch` on this Mac): put a silent stand-in `audioplayer` classdef
  (constructor, `play`, `stop`) first on the path so nothing plays, start a
  `timer` whose callback finds the uifigure by name ("Listening
  experiment") and calls `fig.WindowKeyPressFcn(fig, struct('Key','f'))` or
  a button's `ButtonPushedFcn`; `exportapp(fig, file)` screenshots it.
  Gotcha hit (2026-09-17): an `onCleanup(@() delete(fig))` inside a
  function whose nested functions are the figure's callbacks never fires
  (the callbacks keep that workspace alive), and with `CloseRequestFcn` =
  abort the leftover window could not be closed. Now `delete(fig)` is
  explicit (try/catch around `runTrials`), and a 2nd close request deletes
  a window orphaned by ctrl-C. Verified for normal end and Esc; the
  close-box and error paths were not run.
  Stale-stimulus trap: the experiment reuses whatever WAVs are in
  `stimuli/`; after a synthesis change pass `'Regenerate', true` or rewrite
  the set. Simulated recovery (pse 0.45, σ 0.06, 11 levels): pse unbiased,
  SD 0.024 @ 10 reps; with 3 % lapses `Lapse="none"` inflates σ ~50 %,
  "symmetric" does not — keep it the default.
- `lib/` is not on the MATLAB path by itself: `TestSynthSibilant` and
  `ValidateSynthSibilant` `addpath` it (and the experiment repo's
  `code/analysis/lib`) at the top. `SynthSibilant`, `BuildSibilantModel`
  and `WriteSibilantContinuum` use only local functions. The
  `perception_experiment/` functions `addpath` the repo root themselves.
- **Docs sweep after every code change (Paul's rule, 2026-09-16).** Whenever
  code changes, re-read every `.m` doc header (the `%` block under the
  `function` line, in all top-level files and `lib/`), `README.md` and this
  `CLAUDE.md`, and fix anything the change made stale: algorithm
  descriptions, option lists, file tables, `.gitignore` contents, model
  fields, validation numbers (re-run `TestSynthSibilant` /
  `ValidateSynthSibilant` if the synthesis or analysis changed) and the
  design-decision entries. Do it in the same commit as the code change.
- Model struct fields: `Fs, tokens, vowelOf, classOf, nSlices, logGridHz,
  lpcOrder, preEmph, lpcHop, talkerIds, talkers(i).words(j).{sibSpecDb,
  sibPeakHz, sibEnvDb, sibDurS, sibLevelDb, vowLsf, vowRmsDb, vowDurS,
  vowF0Hz, vowSpecDb, n, included}, talkers(i).templates(v).{residual{},
  vowDurS, f0Hz, source}`. Changing the analysis = rebuild + re-validate.

## Open ideas (not done, ask Paul first)

- Vowel duration/F0 varying with `a` would need pitch-synchronous
  time-scaling of the residual or a synthetic glottal source.
- A second landmark (e.g. the lower −6 dB edge) if the single-landmark morph
  proves perceptually uneven; the ~11 kHz /s/ peak currently fades in by
  level rather than gliding.
- Include pert0 sham adaptation trials (also unshifted) to thicken the
  she/shoe estimates; nothing can thicken see/sue (5 trials each).
- Listening tests / a pilot to locate the category boundary in `a` (the
  tooling now exists: `perception_experiment/`; still nobody has run it); the
  pilot could also compare the fixed vowel with `"morph"`, and a Lane-style
  level-only path with the mel morph.
- Appraisal of Lane et al. 2007 (2026-09-17, `papers/`): their continuum
  interpolates Klatt formant amplitudes at fixed frequencies, so
  intermediate spectra are broad/bimodal; on our data the /ʃ/ resonance is
  not present as a peak in /s/ (27 % of cells), so in software it collapses
  to the dB cross-fade already rejected. Kept the mel morph; borrowed the
  fixed vowel; step re-spacing by pilot still to do.
