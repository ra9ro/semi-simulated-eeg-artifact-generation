# semi-simulated-eeg-artifact-generation
## Code scope

This repository contains the MATLAB code used to generate semi-simulated EEG data.

The reference dataset is available in Zenodo under DOI 10.5281/zenodo.23185596.

The script operates directly on the WEEG-ARTS dataset and uses the manually annotated EEG recordings contained in `derivatives/manualAnnotations/`.

The code can be adapted to compatible EEG datasets containing clean baseline recordings and manually annotated artifact segments.

The artifact-removal methods subsequently applied to the semi-simulated data were implemented using publicly available code released by the respective authors. The corresponding implementations can be found at the following references:

* **Method Singular Spectrum Analysis (SSA):** Hu, H., Guo, S., Liu, R., & Wang, P. (2017). An adaptive singular spectrum analysis method for extracting brain rhythms of electroencephalography. PeerJ, 5, e3474.

* **Method Variational Mode Extraction with Discrete Wavelet Transform (VME–DWT):** Shahbakhti, M., Beiramvand, M., Nazari, M., Broniec-Wójcik, A., Augustyniak, P., Rodrigues, A. S., ... & Marozas, V. (2021). VME-DWT: An efficient algorithm for detection and elimination of eye blink from short segments of single EEG channel. IEEE Transactions on Neural Systems and Rehabilitation Engineering, 29, 408-417.

* **Method Multivariate Empirical Mode Decomposition with Artifact Subspace Reconstruction (MEMD–ASR):** Arpaia, P., Esposito, A., Natalizio, A., Parvis, M., & Pesola, M. (2023). Low-density EEG correction with multivariate decomposition and subspace reconstruction. IEEE Sensors Journal, 23(19), 23621-23628.

* **Method IMU-integrated Artifact Subspace Reconstruction (IMU–ASR):** Kumaravel, V. P., & Farella, E. (2023, December). IMU-integrated Artifact Subspace Reconstruction for Wearable EEG Devices. In 2023 IEEE International Conference on Bioinformatics and Biomedicine (BIBM) (pp. 2508-2514). IEEE.

* **Method Denoising Autoencoder (DAE):** Saleh, M., Xing, L., & Casson, A. J. (2025). EEG artifact removal at the edge using AI hardware. IEEE Sensors Letters, 9(6), 1-4.

The original methodological references should also be cited when using these implementations.

## Dataset organization after download

The WEEG-ARTS dataset is distributed on Zenodo as multiple archives because of file-size constraints. After downloading the dataset, the archives should be extracted and their contents combined to reconstruct the original dataset structure before running the code.

The resulting directory should have the following organization:

```text
WEEG-ARTS/
├── dataset_description.json
├── participants.json
├── participants.tsv
├── README.md
├── sub-01/
├── sub-02/
├── ...
├── sub-21/
└── derivatives/
    ├── manualAnnotations/
    │   ├── sub-01/
    │   ├── sub-02/
    │   └── ...
    └── semiSimulated/
        ├── sub-01/
        ├── sub-02/
        └── ...
```

# Semi-Simulated EEG Data Generation

## Overview

This repository provides the MATLAB code used to generate the semi-simulated EEG data from clean EEG baseline segments and manually annotated artifact recordings.

The code is divided into two files:

- `generate_semisimulated_data.m`: main script used to apply the procedure to the dataset.
- `createSemiSimulatedEEG.m`: standalone function implementing the core semi-simulation procedure. It performs artifact isolation by zero-padding, smoothing, artifact re-extraction, SNR-based scaling, and insertion into clean EEG.

## Requirements

The code was prepared for:

- MATLAB R2026a or a compatible release.
- Signal Processing Toolbox, including `edfinfo`, `edfheader`, and `edfwrite`.
- EEGLAB available on the MATLAB path, including the functions `pop_biosig`, `eeg_emptyset`, and `eeg_checkset`.

The EEG recordings are expected to have a sampling frequency of 250 Hz. The scripts do not perform resampling.

The semi-simulation function uses MATLAB `smooth` when available; `movmean` is used as a fallback for the moving-average operation.

## Expected input data

The main script expects the dataset to be organized in BIDS-like folders.

Raw EEG files are expected under:

```text
<Main root>/sub-*/ses-*/eeg/*_eeg.edf
```

Manually annotated artifact recordings are expected under:

```text
<Main root>/derivatives/manualAnnotations/sub-*/ses-*/eeg/
    *_desc-manualannotation_eeg.edf
```

When a corresponding `*_events.tsv` file is available, event markers are read from the TSV file. The file must contain the columns `sample` and `marker_label`. If no events TSV file is available, EDF+ annotations are used instead.

The main script also reads `sub-*_sessions.tsv`, when available, to honor entries marked with `derivative_status = excluded`.

## Files

### `generate_semisimulated_data.m`

This is the main script and should normally be the entry point for reproducing the semi-simulated dataset.

The script:

1. Defines the dataset location and processing parameters.
2. Identifies the participants and EEG devices to process.
3. Loads the baseline EEG recordings.
4. Selects the clean ground-truth segment between baseline markers `201` and `202` after removing predefined excluded intervals.
5. Loads the manually annotated artifact recordings.
6. Identifies the manually selected artifact intervals from the artifact markers.
7. Defines dataset-specific settings, such as retaining only the first 2 s of the isolated `Switch_Artifact` segment.
8. Calls `createSemiSimulatedEEG.m` to generate the contaminated signals at the requested SNR levels.
9. Adds artifact start/end markers to the generated recordings.
10. Saves the clean ground-truth and semi-simulated contaminated signals as EDF+ files.

The main script therefore documents how the general semi-simulation procedure was applied to the specific dataset.

### `createSemiSimulatedEEG.m`

This function contains the core semi-simulation procedure and does not depend on participant IDs, paths, EEG devices names, or artifact names.
The semi-simulation procedure was informed by methodological approaches described by Alkhoury et al. [1] and Cui et al. [2] for constructing artifact-contaminated EEG through artifact isolation, additive contamination and controlled SNR scaling.

Its main inputs are:

- `cleanData`: clean EEG segment, organized as channels x samples.
- `artifactRecording`: EEG recording containing the manually selected artifact.
- `artifactStartSample`: first sample of the manually selected artifact interval.
- `artifactEndSample`: last sample of the manually selected artifact interval.
- `Fs`: sampling frequency in Hz.
- `simParams`: structure containing the semi-simulation parameters.

The function performs the following operations:

1. A zero-valued matrix with the same size as the artifact recording is created.
2. Only the manually selected artifact interval is copied into the zero-padded matrix.
3. Moving-average smoothing is applied channel-wise to the complete zero-padded signal.
4. The smoothed artifact interval is re-extracted.
5. If a maximum artifact duration is specified, only the corresponding initial portion of the isolated artifact is retained.
6. Artifact insertion positions are converted from seconds to samples and checked for validity and overlap.
7. For each insertion position, the corresponding ground-truth EEG window is selected with the same duration as the isolated artifact.
8. The squared L2 norms of the local ground-truth window and isolated artifact are computed jointly over all EEG channels and samples.
9. For each requested SNR, a separate scaling factor is computed for each artifact occurrence and the scaled artifact is added within the corresponding insertion window.
10. One semi-simulated EEG matrix is returned for each requested SNR value.

The parameters used by the current main script are defined in the `SEMI-SIMULATION PARAMETERS` section.

## SNR scaling

SNR scaling is performed locally for each artifact occurrence. For the `k`-th insertion, the reference EEG is the ground-truth window corresponding exactly to the interval in which the isolated artifact is added. The reference window and artifact therefore have the same duration and include all EEG channels.

The squared L2 norm is evaluated jointly over all channels and samples using `sum(...(:).^2)`. For each target SNR, a separate scaling factor is computed for each insertion window.

When more than one artifact occurrence is inserted into the same ground-truth signal, each occurrence is therefore scaled independently so that the requested SNR is defined with respect to the local ground-truth samples in its own insertion window.


## How to run the code

Place both MATLAB files in the same folder, or make sure that both files are available on the MATLAB path.

First, add EEGLAB to the MATLAB path. Then open `generate_semisimulated_data.m` and set the root folder of the local dataset:
```matlab
cfg.BidsRoot = 'C:\path\to\WEEG-ARTS';
```


By default, regenerated files are written to:
```text
<Main root>/derivatives/semiSimulated_regenerated/
```

This prevents accidental overwriting of previously generated data. The output location can be changed through:

```matlab
cfg.OutputDerivativeRoot = fullfile(cfg.BidsRoot, 'derivatives', 'semiSimulated_regenerated');
```

To process all available participants, leave:
```matlab
cfg.Subjects = {};
```

To process only selected participants, specify their BIDS labels, for example:
```matlab
cfg.Subjects = {'sub-01','sub-02'};
```

The EEG systems can be selected using:
```matlab
cfg.Systems = {'sys1','sys2'};
```

## Outputs

The script generates EDF+ files containing:

- the clean ground-truth EEG segment selected from the baseline recording;
- semi-simulated EEG signals obtained by adding one isolated artifact to the clean EEG at each requested SNR level.

The contaminated EDF+ files also contain the artifact start and end markers corresponding to the inserted artifact intervals.

## Reproducibility notes

Several choices in `generate_semisimulated_data.m` are specific to the dataset, including participant-specific baseline exclusions, artifact marker definitions, EEG-device/session conventions, insertion-time rules, and the 2 s limit applied to `Switch_Artifact`.

`createSemiSimulatedEEG.m` is intentionally separated from these dataset-specific definitions so that the core semi-simulation procedure can be inspected and reused independently.

When reusing the function with other datasets, the user is responsible for providing the clean EEG, the artifact recording, the manually selected artifact interval, the sampling frequency, insertion times, and the desired semi-simulation parameters.


## References

[1] Alkhoury, L., Scanavini, G., Louviot, S., Radanovic, A., Shah, S. A., & Hill, N. J. (2025). Artifact-reference multivariate backward regression (ARMBR): a novel method for EEG blink artifact removal with minimal data requirements. Journal of Neural Engineering, 22(3), 036048.

[2] Cui, H., Li, C., Liu, A., Qian, R., & Chen, X. (2023). A dual-branch interactive fusion network to remove artifacts from single-channel EEG. IEEE Transactions on Instrumentation and Measurement, 73, 1-12.
