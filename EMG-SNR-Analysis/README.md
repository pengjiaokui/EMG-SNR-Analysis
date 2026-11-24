# EMG SNR analysis (MATLAB)

This repository contains a single-channel surface electromyography (sEMG) analysis GUI, `emgSNR.m`. It was organized for transparent, reproducible reporting of the **active-to-rest mean-square amplitude ratio** used in the CMC/PVCL hydrogel-electrode experiments.

## Data acquisition versus analysis

The GUI **does not record EMG**. The experiment used a custom acquisition circuit and microcontroller firmware, a serial/Bluetooth link, and the third-party VOFA+ application for data reception and export. MATLAB is used only for **offline analysis** of exported CSV recordings.

The analogue front end was designed with a 20–500 Hz passband and a 50 Hz power-line notch. The MATLAB analysis itself does **not** add a digital bandpass or notch filter.

**Sampling-rate discrepancy to resolve before publication:** the historical MATLAB analysis assumed **2000 Hz**, whereas an independently shared STM32 firmware configuration specifies a nominal **1000 Hz** ADC trigger rate. The firmware setting alone does not validate continuous, loss-free CSV output. Identify which firmware, rate, and export were used for each reported EMG recording. Correct the analysis configuration and re-evaluate historic intervals/results if necessary; do not silently treat the 2000-Hz assumption as an experimentally confirmed rate.

## Requirements

- MATLAB R2019a or later (`readmatrix`)
- Signal Processing Toolbox (`pwelch`, used for visualization only)
- A CSV containing the EMG channel in its first column, with the same import convention as the original study.

## Usage

Place `emgSNR.m` on the MATLAB path. From the MATLAB Command Window:

```matlab
emgSNR();                         % choose a CSV from a file dialog
emgSNR('recording.csv');          % legacy assumption: fs = 2000 Hz
emgSNR('recording.csv', 1000);    % explicitly specify fs if verified
```

The `2000`-Hz legacy default emits a warning. **Specify the real effective sampling rate once independently established.** The optional sampling-rate argument controls the time axis, slider-to-sample indexing and PSD frequency axis; it does **not** alter the underlying SNR formula.

## Analysis steps (historical calculation retained)

1. Read the first column of the CSV with `readmatrix`, then discard the first matrix row: `rawEmg = csvData(2:end,1)'`. This is how the original script selected samples. **Check the actual VOFA+ CSV structure before using this legacy import rule**: `readmatrix` may already skip textual headers, in which case another valid sample would be dropped.
2. Subtract the global mean of the selected recording: `emg = rawEmg - mean(rawEmg)`.
3. Use the GUI sliders to choose a **rest** segment and an **active** muscle-contraction segment. Default sliders show 0.5–1.5 s (rest) and 3–4 s (active), but these are **not** prescribed analysis intervals.
4. In the study, the initial portion of each CSV was collected with the muscle relaxed. Approximately **4 s** of this stable resting period were manually selected as the common noise-reference segment for that CSV.
5. For each contraction in the same recording, manually select an active segment matched to its actual duration. Calculate and record the displayed SNR (dB). Repeat for the desired number of contractions, reusing the same resting segment.
6. Calculate the final result **outside the GUI**, by taking the **arithmetic mean of the recorded dB values**. The script does not automatically process a batch of intervals or calculate the final mean.

The computation for one selected contraction is:

```matlab
noise_power  = mean(restSamples.^2);
signal_power = mean(activeSamples.^2);
SNR_dB       = 10*log10(signal_power/noise_power);
```

Here `noise_power` and `signal_power` are **mean squared amplitudes** (not measured electrical power in watts). Their units cancel in the ratio. The calculation does not explicitly remove noise power from the active segment. No additional filtering is performed. Power spectral density obtained from `pwelch` is **for display only**.

If the selected active windows yield values `SNR_1` through `SNR_K` in dB, report `mean([SNR_1, ..., SNR_K])` (arithmetic mean in dB), not `10*log10(mean(signal_power)/noise_power)`.

## Important notes on units and timing

- The first-column data may be **raw ADC counts**, not calibrated electrode voltages. The output waveform axis is therefore labeled `CSV units` rather than mV. Do not relabel data as mV without documenting a calibrated conversion.
- Valid time intervals are derived from `sample_index / fs`. Inadequate verification of the effective sampling frequency can change which samples are selected as the resting or active interval and invalidate comparisons.
- The current serial protocol may not include per-sample timestamps or sequence numbers. An assumed nominal rate is **not independent evidence of continuous uniformly spaced samples**.
- The exact legacy rounding convention is preserved: `max(1,round(start*fs))` through `min(N,round(end*fs))`, using inclusive MATLAB indices.
- No personally identifying recordings or participant datasets are included in this repository.

## Reproducibility information still required

Before referring to these files in a paper, document the MATLAB release, experimental acquisition firmware commit, measured effective sampling rate, VOFA+ version/serial protocol, CSV first-row structure, a redacted example CSV, and the selected time windows used for reported data. Retain the raw and corrected data separately if the acquisition settings are revised.

## Availability and licensing

The script can be used for research review and replication. No open-source license has yet been selected by the author; add an appropriate `LICENSE` after the author decides the conditions under which reuse is permitted. Do not describe this project as released under a license that has not been granted.
