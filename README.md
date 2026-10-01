# sibilant_synth

A data-driven MATLAB synthesizer for **she / see / shoe / sue** tokens whose
sibilant lies anywhere on a continuum from /ʃ/ (`a = 0`) to /s/ (`a = 1`),
built from the recordings of the `sibilant_experiment` cohort (72 talkers),
for a two-alternative forced-choice perception experiment ("did you hear
*she* or *see*?").

```matlab
[y, Fs, info] = SynthSibilant(0.35, "i");              % random talker, she-ish
[y, Fs, info] = SynthSibilant(1.0,  "u", "pert6P02");  % "sue" from one talker
sound(y, Fs)
SynthSibilantTalkers()                                 % the 72 talker ids
WriteSibilantContinuum("stimuli", 'A', 0:0.1:1)        % WAVs + manifest.tsv (stimuli/ is gitignored)

addpath perception_experiment
[T, f] = RunPerceptionExperiment("P01", 'A', 0:0.1:1, 'Reps', 10, 'Vowels', "i");   % the listening experiment
fit = FitPsychometric(f);                              % MLE psychometric function, boundary + CI
```

`a` is the continuum position, `vowel` is `"i"` (she/see) or `"u"`
(shoe/sue), and the optional third argument is a talker id or `"random"`.
Options: `VowelContext` (a fixed weight in [0, 1] between the talker's
/ʃ/-context and /s/-context vowel filter, default 0.5, i.e. **the same
neutral vowel at every `a`**; aliases `"sh"`, `"mid"`, `"s"`; or `"morph"`
to let the coarticulation follow `a`), `Seed` (noise, talker and template
choice), `Template` (which of the talker's two excitation templates),
`Level` (vowel RMS in dBFS, default −20), `PadMs` (silence at each end,
default 50), `SibDur` (sibilant duration in s), `Play`, `Model`. `info`
returns the talker, the two words interpolated between, durations, sample
indices of the sibilant and vowel, the landmark frequency per time slice,
the vowel weight used (`vowelA`), the template and seed, and any
peak-limiting scale factor.

## Files

| File | What it does |
| --- | --- |
| `SynthSibilant.m` | the synthesizer (reads `sibilant_model.mat`) |
| `SynthSibilantTalkers.m` | lists the talker ids in the model |
| `WriteSibilantContinuum.m` | writes `<talker>_<vowel>_a<a>.wav` (16-bit) for every talker × vowel × `a`, plus `manifest.tsv` (one row per file, incl. `vowel_context` and `template`; both default to fixed values, 0.5 and 1, so a continuum's vowel is identical end to end) |
| `BuildSibilantModel.m` | learns `sibilant_model.mat` from the raw recordings (needs the Dropbox raw data and the experiment repo; ~40 s with the Parallel toolbox) |
| `TestSynthSibilant.m` | detailed per-talker check with figures and WAVs → `test_output/` |
| `ValidateSynthSibilant.m` | whole-spectrum validation over all talkers → `test_output/validation_all.{tsv,png}` |
| `perception_experiment/` | `RunPerceptionExperiment.m` (GUI, two-alternative identification), `PreparePerceptionStimuli.m` (synthesises the WAVs the experiment needs and `stimuli/` lacks), `FitPsychometric.m` (maximum-likelihood psychometric function); see [below](#perception-experiment-perception_experiment) |
| `lib/` | shared measurement helpers (mid-sibilant multitaper spectrum, whole-spectrum features, discriminant) |
| `sibilant_model.mat` | the learned model, 72 talkers, ~22 MB |
| `.gitignore` | `test_output/` and `stimuli/` (both regenerable), `perception_experiment/data/` (participant data), MATLAB autosave files, `.DS_Store` |

MATLAB R2026a with the Signal Processing Toolbox (`pmtm`, `lpc`,
`poly2lsf`, `lsf2poly`); the Parallel Computing Toolbox is optional
(`BuildSibilantModel` uses `parfor`). The synthesizer needs only the `.mat`;
the raw data and the experiment repo are needed to rebuild it and to run
the validation.

## How the model is built (`BuildSibilantModel`)

For every participant except cohort `ryan` (no practice block, so no
see/sue), every **unshifted** trial (practice and baseline blocks) of the
four words is analysed from the microphone channel between the hand-scored
boundaries (`scored_data/<pid>_scored.tsv`). Per talker × word:

- **Sibilant spectrum**: multitaper spectra (40 ms windows, 7 tapers) at 5
  equally spaced points across the sibilant, resampled onto a 1/48-octave
  grid (100 Hz to Nyquist), averaged over trials in linear power, then
  smoothed (Gaussian, σ = 1/24 octave). The 5 slices capture within-sibilant
  dynamics such as the anticipatory lip rounding before /u/.
- **Spectral landmark** per slice: the power-weighted log-frequency centroid
  of the region within 6 dB of the in-band maximum (1.8–5 kHz for /ʃ/,
  3–10 kHz for /s/). This is what the morph aligns.
- **Sibilant RMS envelope** (25 points in normalised time), **duration**
  (median) and **level relative to the following vowel** (mean of the
  sibilant/vowel RMS ratio in dB).
- **Vowel filter**: order-40 LPC (pre-emphasis 0.97, 30 ms Hamming windows)
  in 40 normalised-time frames, converted to line spectral frequencies (LSF)
  and averaged in that domain, which keeps formant bandwidths (averaging
  spectra and refitting broadens them). Mean **RMS contour**, median
  duration and median mid-vowel F0 are stored alongside.
- **Excitation templates** per talker × vowel: the LPC residuals of the two
  she (/i/) or shoe (/u/) recordings whose vowel duration is closest to the
  word's median.

Trials with clipping (peak > 0.99), sibilants < 60 ms or vowels < 80 ms are
dropped. For words with ≥ 10 trials, duration and level outliers (> 3 robust
SD) are dropped too, unless fewer than 3 trials would remain; see/sue (5
trials each, robust SD unreliable) are never outlier-filtered. `pert6P08` is
excluded (no usable *see* trials). Per talker there are at most 30 she and
30 shoe (5 practice + 25 baseline) and 5 see and 5 sue (practice only).

## How a token is synthesised (`SynthSibilant`)

**Sibilant.** White noise is shaped frame by frame (STFT, 1024-point frames,
75 % overlap) by a time-varying envelope interpolated between the 5 slices.
At `a = 0` and `a = 1` the envelope is the talker's mean /ʃ/ or /s/ spectrum
*in the requested vowel context* (she vs shoe, see vs sue). In between, the
two spectra are **morphed rather than mixed**: the frequency axis is warped
piecewise-linearly **on the mel scale** (anchored at the grid ends and the
landmark) so that the two landmarks coincide at
`mel⁻¹((1−a)·mel(f_ʃ) + a·mel(f_s))`, then the levels are interpolated bin
by bin. Equal steps in `a` are equal mel steps (mel = 2595·log10(1 + f/700));
`info.sibPeakHz` reports the landmark per slice. The main energy region
glides continuously from the /ʃ/ to the /s/ frequency and intermediate
spectra stay unimodal, unlike the double-peaked spectra of a cross-fade.
Duration (log-linear), RMS envelope and level relative to the vowel (linear
in dB) are interpolated with `a` as well.

**Vowel.** The talker's LSF trajectories after /ʃ/ and after /s/ are
interpolated frame by frame with the `VowelContext` weight, converted back
to an all-pole filter updated every 5 ms, driven by one of the talker's own
LPC residuals and de-emphasised, so pitch, voice quality and breathiness are
the talker's own. **By default the weight is 0.5**, so every token of a
continuum carries the same vowel (bit-identical after the 10 ms join) and
the continuum differs only in the sibilant, as in Lane et al. (2007) and
Shiller et al. (2009), who concatenated one natural vowel to every step. The
midpoint favours neither category, the she/see coarticulatory difference is
small anyway (mid-vowel F2 a few tens of Hz; F2 onset ~100 Hz before /u/,
~15 Hz before /i/, medians over talkers), and it leans mostly on the
better-estimated /ʃ/-context vowel (30 trials vs 5). `VowelContext =
"morph"` uses `a` as the weight so the coarticulation (mainly the formant
onsets) moves with the sibilant; any fixed weight in [0, 1] (aliases
`"sh"`, `"mid"`, `"s"`) is also accepted. The RMS contour follows the same
weight; vowel duration and F0 are fixed by the excitation template.
Sibilant and vowel are joined with a 10 ms cross-fade, and the vowel ends
with a 40 ms raised-cosine ramp (the scored vowel end is still voiced,
median −17 dB re mid-vowel, and some recordings end with a phonation click
that the ramp has to cover). The vowel RMS is set to
`Level` dBFS with the sibilant at its data-driven level relative to it, and
the token is scaled down only if its peak would exceed 0.99
(`info.scaledBy`).

## Validation

`TestSynthSibilant` and `ValidateSynthSibilant` measure the synthetic
sibilant as the experiment measures real ones (three 50 ms multitaper
windows at mid-sibilant) and compare **whole level-normalised spectra**
(1/12 octave, 500 Hz–16 kHz, 61 bins, mean level removed) with the per-trial
spectra in `extracted_data/participants/*_spectra.tsv`. Results from the
full run (72 talkers × 2 vowels = 144 cells, `a = 0:0.1:1`):

- **Endpoint fit**: RMS over bins of (synthetic − real mean) / real SD (SD
  floored at 1 dB). For scale, each real trial scored leave-one-out against
  the other trials of its word gives medians of 0.69 (/ʃ/ words) and 0.94
  (/s/ words). The synthetic endpoints score 0.53 and 0.63 and lie below
  the real trials' median in 98 % of cells: inside the talker's own trial
  cloud, closer to its mean than a typical real trial.
- **Continuum position**. (i) On each talker's own /ʃ/→/s/ spectral axis
  (0 = real /ʃ/ mean, 1 = real /s/ mean) the position runs from −0.02 to
  0.97 (medians), is monotonic in 100 % of cells and moves 0.08–0.12 per
  0.1 step in `a`. (ii) A shrinkage Fisher discriminant per vowel, trained
  on all real trials of that vowel from all talkers (4,972 trials, 99.5 %
  correct) and scaled so the real class means score 0 and 1, puts the
  endpoints at 0.04 and 1.02 with a mildly S-shaped mean course; on this
  population axis individual curves wobble by a few hundredths (~40 %
  strictly monotonic), less than the within-talker spread of real trials
  (SD ≈ 0.1).
- **Vowel** (endpoints synthesised with `VowelContext = "morph"`, since only
  then does the vowel follow the word): mid-vowel F1/F2 of the synthetic
  endpoints vs the talker's real means (`all_extracted.tsv`) have a median
  error of −4/−5 Hz after /ʃ/ and −6/−4 Hz after /s/ (MAD ≤ 31 Hz), with F2
  passing the tracker's confidence gate in 92 % / 85 % of tokens. The
  tracker's search ranges come from the roster's `sex` column, and the
  reference extraction uses the same roster, so both sides use the same
  per-talker presets. `TestSynthSibilant` overlays the synthetic and real
  F1/F2 tracks, including the she–see difference at vowel onset.

`TestSynthSibilant` writes figures (`test_output/fig/`) and WAVs to listen
to (`test_output/wav/`); `ValidateSynthSibilant` prints the all-talker
summary and writes `test_output/validation_all.tsv`. `test_output/` is not
tracked, so regenerate it after cloning. Both scripts need the experiment
repo with a `<pid>_spectra.tsv` for every talker (gitignored there;
regenerate a missing one with `extract_spectra` in the experiment repo).

## Perception experiment (`perception_experiment/`)

```matlab
addpath perception_experiment
[T, f] = RunPerceptionExperiment("P01");                                  % she/see, a = 0:0.1:1, 10 reps
[T, f] = RunPerceptionExperiment("P02", 'A', 0:0.2:1, 'Reps', 15, 'Vowels', ["i" "u"], 'ShSide', "right");
fit = FitPsychometric(f);
```

**`RunPerceptionExperiment(participant, ...)`** plays one token per trial;
the participant says whether it began with /ʃ/ or /s/ by clicking one of
two large buttons or pressing a key (`F` = left, `J` = right; `Keys` changes
them, `ShSide` puts /ʃ/ on the right for counterbalancing). The buttons read
*she*/*see* for `'Vowels', "i"` (default), *shoe*/*sue* for `"u"`, and
*she / shoe* and *see / sue* when both vowels are intermixed (`["i" "u"]`).
Options: `A` (levels, default `0:0.1:1`, at most 3 decimals), `Reps`
(repetitions per level, default 10), `Vowels`, `Talkers` (default
`"pert4P17"`; several are intermixed), `Practice` (default 3), `ItiS`
(0.75 s), `BreakEvery` (self-paced break every n trials, default off),
`Seed`, `WindowState`, `StimDir`, `DataDir`, `Regenerate`.

*Trial order*: every talker × vowel × level combination, `Reps` times; each
repetition is a freshly shuffled block of all combinations, so the order is
random but the levels are spread evenly over the session (`Seed` makes it
reproducible). `Reps` can also be a vector with one count per level of `A`,
to spend fewer trials on the endpoints and more near the boundary: there
are then `max(Reps)` blocks and a level with fewer repetitions is placed in
that many of them, evenly spaced from a random start. Suggested weighted
design for a boundary near `a = 0.5`, 17 levels denser near the middle:
`'A', [0 0.2 0.3 0.35 0.4:0.025:0.6 0.65 0.7 0.8 1], 'Reps',
[3 3 4 5 7 8 9 10 12 10 9 8 7 5 4 3 3]` (110 trials;
`[5 5 6 8 10 12 13 15 17 15 13 12 10 8 6 5 5]` for 165). In simulation it
estimates the pse with an SD of 0.011–0.020 per session, 25–30 % better
than 10 repetitions of each of `0, 0.3:0.05:0.7, 1`, and the slope to about
±20 %. The session opens with a **practice block** of the endpoint tokens
(`a = 0` and `a = 1` of every talker × vowel, whatever `A` is; `Practice`
shuffled repetitions of each, 0 = none), run like the main trials with no
feedback and followed by a screen announcing the main part.

*Stimuli* are WAV files, never synthesised during the trials. Before the
first trial `PreparePerceptionStimuli` looks in `StimDir` (default
`stimuli/`) for `<talker>_<vowel>_a<a>.wav`, synthesises whatever is missing
in one batch with the `WriteSibilantContinuum` defaults (fixed neutral
vowel, template 1, −20 dBFS) and a noise seed derived from the file name,
appends the new rows to `manifest.tsv`, and reads all WAVs into memory.
After a change to the synthesis pass `'Regenerate', true` once (or rewrite
the set with `WriteSibilantContinuum`). Set the listening level with the
system volume.

*A trial*: buttons greyed, `ItiS` of silence, the token plays, the buttons
become active when it ends (earlier presses and clicks are ignored), the
chosen button lights up for 150 ms. No feedback, no time limit. `Esc` or
closing the window ends the session; every trial is written to disk as soon
as it is answered.

*Data*: `data/<participant>_<yyyymmdd_HHMMSS>.tsv`, one row per trial:
`participant`, `phase` (practice / main), `trial` (within phase), `block`
(repetition; 0 in practice), `talker`, `vowel`, `a`, `filename`, `response`
(`sh` / `s`), `resp_s` (0 = /ʃ/, 1 = /s/), `word`, `input` (key / button),
`rt_s` (from playback start; includes the unknown audio output latency),
`sh_side`, `time`; plus a `.json` with the options, the trial-order seed and
whether the session completed. `data/` is gitignored.
`'Simulate', [pse sigma lapse]` replaces window and participant by a
simulated logistic listener, to try the pipeline.

**`FitPsychometric(file, ...)`** reads one or more data files (or a trial
table), drops the practice trials and fits, per vowel by default (`By`),

    P("s" | a) = γ + (1 − γ − λ) · F((a − μ) / σ)

by maximum likelihood (binomial log-likelihood over the levels, `fminsearch`
from the best points of a coarse grid; no toolbox needed). `F` is the
logistic (default) or the cumulative normal (`Function`); γ and λ are lapse
rates, by default one symmetric rate in [0, 0.1] (`Lapse`: `"symmetric"`,
`"free"`, `"none"`; `LapseMax`). Reported per fit: the **category boundary**
(`pse`, where P("s") = 0.5), σ, the slope at the boundary, the interquartile
width of `F`, the lapse rates, the deviance, 95 % percentile intervals from
a parametric bootstrap (`NBoot`, default 1000) and a bootstrap
goodness-of-fit p value. It prints a summary, writes `<data file>_fit.tsv`
and saves `<data file>_fit.png` (proportions with Wilson intervals, fitted
curves, boundary and its interval).

Checked on simulated listeners (boundary 0.45, σ 0.06, 11 levels, 300 data
sets per cell): the boundary is recovered without bias (SD 0.024 at 10 reps
per level, 0.018 at 20). Without lapses the symmetric-lapse fit costs
nothing (σ 0.053 vs 0.055 for `"none"`); with 3 % lapses `"none"`
overestimates σ by ~50 % (0.092) while the default recovers it (0.058),
hence the default. At 10 reps per level σ is imprecise for one participant
(RMSE ≈ 0.02); use more repetitions or finer levels near the boundary if
the slope matters. The GUI was tested with injected key presses and clicks;
only pilot sessions have been run so far.

## Known limitations

- Vowel duration and F0 come from the excitation template and never vary
  with `a`; with the default fixed vowel nothing in the vowel does, and with
  `VowelContext = "morph"` only the vocal-tract filter and RMS contour do.
- Only 5 see and 5 sue trials exist per talker, so the /s/ endpoints and
  the post-/s/ vowel filters rest on fewer trials than the /ʃ/ side.
- The roster's `sex` column affects only the formant-tracking presets used
  in validation, not the synthesis. It is the experimenter's by-ear rating
  of each voice, not self-report; future participants will be asked their
  sex and gender.
- The morph aligns one landmark (the main energy region); secondary
  features such as the /s/ peak near 11 kHz appear or fade by level rather
  than gliding.
- The validation is acoustic. Only pilot listening sessions have been run,
  so the she/see category boundary in `a` is not yet established.
