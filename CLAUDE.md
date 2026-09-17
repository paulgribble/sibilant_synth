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
  an id (72 available, `SynthSibilantTalkers()`). Options `Seed`, `Template`
  (1..2), `Level` (vowel RMS dBFS, −20), `PadMs`, `SibDur`, `Play`, `Model`.
  Model is loaded once into a `persistent` cache keyed by path.
- `BuildSibilantModel()` — rebuilds the `.mat` (~40 s with parfor over
  talkers). Only needed if the analysis changes or new participants arrive.
- `WriteSibilantContinuum(outDir, ...)` — WAV set + `manifest.tsv` for the
  presentation script. Paul writes to `stimuli/` (gitignored, regenerable;
  rewrite it after any change to the synthesis).
- `TestSynthSibilant()` — 3 talkers, detailed figures + WAVs → `test_output/`.
- `ValidateSynthSibilant()` — all 72 talkers, whole-spectrum stats →
  `test_output/validation_all.{tsv,png}`; ~3 min.
- `lib/` — shared measurement helpers: `measureMidSpectrum` (three 50 ms
  multitaper windows at mid-sibilant, mirrors the experiment's "m" point),
  `spectrumFeatureGrid` / `spectrumFeatures` (1/12-oct, 500 Hz–16 kHz,
  level-normalised), `loadRealSpectra` (reads the experiment's per-trial
  `*_spectra.tsv`), `fitSpectrumLda` / `applySpectrumLda`.

## Data (all external to this folder)

- Raw audio: `/Users/plg/Library/CloudStorage/Dropbox/data/sibilant_experiment/raw_data/<group>/<pid>/*.wav`,
  stereo, **ch1 = mic** (used), ch2 = feedback (ignored). 44.1 kHz for the
  pert cohorts, 48 kHz for ryan (ryan is excluded anyway: no practice block,
  hence no see/sue).
- Experiment repo: `/Users/plg/github/sibilant_experiment` — read its
  `README.md`, `code/analysis/README.md`, `code/analysis/CLAUDE.md` for the
  data conventions. Used here: `participants.tsv` (roster; every row says
  `male` — a placeholder), `scored_data/<pid>_scored.tsv` (sib_start,
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
- **Excitation = the talker's own LPC residual** (two templates per talker ×
  vowel, from the she/shoe trials nearest the median vowel duration), so
  F0/voice quality are real. Consequence: vowel duration and F0 do not vary
  with `a`; only the filter and RMS contour do. Templates come from the /ʃ/
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

## Validation state (2026-09-16, 72 talkers × 2 vowels, re-run after the mel morph)

Endpoint RMS z 0.53 (/ʃ/) / 0.63 (/s/) vs real trials' 0.69 / 0.94 —
synthetic endpoints sit inside every talker's cloud. Talker-own-axis
position −0.02 → 0.97, monotonic in 100 % of cells, steps 0.08–0.12 per 0.1
in a (the switch from log2 to mel changed nothing else here). Pooled discriminant 0.04 → 1.02, mean course mildly S-shaped;
individual curves wobble a few hundredths on that axis (43 % strictly
monotonic; not noise — averaging 8 seeds didn't fix it — but it's the
population axis, not the talker's). Mid-vowel F1/F2 errors median −3/−2 Hz
after /ʃ/, −7/−1 Hz after /s/. Male /i/ F2 often fails `EstimateFormants`'
confidence gate on synthetic AND real trials — a tracker limitation the
experiment repo also notes, not a synthesis defect. **Nobody has listened to
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
  experiment repo (on 2026-09-16 pert6P19 and pert6P20 had none, although
  they are in `all_extracted.tsv` and the model). Regenerate with
  `extract_spectra("<pid>")` there, or pass `'Talkers'` with the subset that
  has spectra; the 70-talker subset reproduced the 72-talker statistics.
- `test_output/` is regenerated by the test/validate scripts and `stimuli/`
  by `WriteSibilantContinuum`; both safe to delete. Both are gitignored
  (along with `*.asv`, `*.autosave`, `slprj/`, `.DS_Store`), so a fresh
  clone has none of it. `sibilant_model.mat` IS tracked.
- `lib/` is not on the MATLAB path by itself: `TestSynthSibilant` and
  `ValidateSynthSibilant` `addpath` it (and the experiment repo's
  `code/analysis/lib`) at the top. `SynthSibilant`, `BuildSibilantModel`
  and `WriteSibilantContinuum` use only local functions.
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
- Listening tests / a pilot to locate the category boundary in `a`.
