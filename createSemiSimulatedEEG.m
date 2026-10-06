function [semiSimulatedData, artifactPositions] = createSemiSimulatedEEG( ...
    cleanData, artifactRecording, artifactStartSample, artifactEndSample, ...
    Fs, simParams)
% Create semi-simulated EEG by adding an isolated artifact to clean EEG.
%
% INPUTS
%   cleanData            - Clean EEG segment [channels x samples].
%   artifactRecording    - EEG recording containing the manually selected artifact.
%   artifactStartSample  - First sample of the manually selected artifact interval.
%   artifactEndSample    - Last sample of the manually selected artifact interval.
%   Fs                   - Sampling frequency in Hz.
%   simParams            - Structure containing:
%       targetSnrDbValues       target SNR values in dB
%       insertSeconds           artifact insertion times in seconds
%       smoothSpanSamples       smoothing span in samples
%       smoothMethod            smoothing method used by MATLAB smooth
%       removeArtifactDc        remove channel-wise artifact mean if true
%       maxArtifactDurationSec  maximum retained artifact duration; Inf = no limit
%
% OUTPUTS
%   semiSimulatedData    - Cell array containing one semi-simulated EEG
%                          matrix for each target SNR value.
%   artifactPositions    - Start/end samples of each inserted artifact window.
%
% The semi-simulation procedure includes:
%   1) zero-padding outside the manually selected artifact interval;
%   2) smoothing of the complete zero-padded trace;
%   3) re-extraction of the artifact interval;
%   4) local artifact scaling according to the target SNR in each insertion window;
%   5) artifact insertion into the clean EEG segment.

%% Artifact isolation
artifactRecording = double(artifactRecording);
cleanData = double(cleanData);

nSamples = size(artifactRecording, 2);
artifactStartSample = max(1, min(nSamples, round(artifactStartSample)));
artifactEndSample = max(1, min(nSamples, round(artifactEndSample)));

if artifactEndSample <= artifactStartSample
    error('Invalid manual artifact window: start %d, end %d.', ...
        artifactStartSample, artifactEndSample);
end

% Zero-pad outside the manually selected artifact interval.
paddedData = zeros(size(artifactRecording));
paddedData(:, artifactStartSample:artifactEndSample) = ...
    artifactRecording(:, artifactStartSample:artifactEndSample);

% Smooth the complete zero-padded trace channel-wise.
smoothedPaddedData = zeros(size(paddedData));
smoothSpanSamples = max(1, round(simParams.smoothSpanSamples));

for ch = 1:size(paddedData, 1)
    x = paddedData(ch, :);

    if exist('smooth', 'file') == 2
        smoothedPaddedData(ch, :) = smooth(x(:), smoothSpanSamples, simParams.smoothMethod).';
    else
        smoothedPaddedData(ch, :) = movmean(x, smoothSpanSamples);
    end
end

% Re-extract the manually selected artifact interval.
artifactData = smoothedPaddedData(:, artifactStartSample:artifactEndSample);

if simParams.removeArtifactDc
    artifactData = artifactData - mean(artifactData, 2);
end

% Optionally retain only the first part of the isolated artifact (cutting the artifact).
if isfinite(simParams.maxArtifactDurationSec)
    maxArtifactSamples = round(simParams.maxArtifactDurationSec * Fs);

    if size(artifactData, 2) > maxArtifactSamples
        artifactData = artifactData(:, 1:maxArtifactSamples);
    end
end

artLen = size(artifactData, 2);

%% Artifact insertion positions
if isempty(simParams.insertSeconds)
    error('insertSeconds cannot be empty.');
end

requestedInsertSeconds = simParams.insertSeconds(:)';

if any(~isfinite(requestedInsertSeconds)) || any(requestedInsertSeconds < 0)
    error('insertSeconds must contain finite non-negative values.');
end

insertSamples = round(requestedInsertSeconds * Fs) + 1;

if numel(unique(insertSamples)) ~= numel(insertSamples)
    error('Two or more insertion times map to the same sample.');
end

[insertSamples, sortIdx] = sort(insertSamples);
requestedSecondsSorted = requestedInsertSeconds(sortIdx);
artifactEndSamples = insertSamples + artLen - 1;

if any(artifactEndSamples > size(cleanData, 2))
    badIdx = find(artifactEndSamples > size(cleanData, 2), 1, 'first');
    error(['Manual insertion at %.3f s exceeds the clean EEG length ', ...
        'for this artifact.'], requestedSecondsSorted(badIdx));
end

for k = 2:numel(insertSamples)
    if insertSamples(k) <= artifactEndSamples(k-1)
        error(['Manual insertion windows overlap. Artifact duration: ', ...
            '%.3f s.'], artLen / Fs);
    end
end

artifactPositions = [insertSamples(:), artifactEndSamples(:)];

%% Local SNR scaling and semi-simulated data generation
% Squared L2 norm of the isolated artifact over all channels and samples.
artifactEnergy = sum(artifactData(:).^2);

if ~isfinite(artifactEnergy) || artifactEnergy <= 0
    error('Artifact energy is invalid.');
end

% Squared L2 norm of the ground-truth EEG in each insertion window.
referenceEnergy = zeros(numel(insertSamples), 1);

for k = 1:numel(insertSamples)
    idx = insertSamples(k):artifactEndSamples(k);
    referenceWindow = cleanData(:, idx);
    referenceEnergy(k) = sum(referenceWindow(:).^2);
end

if any(~isfinite(referenceEnergy)) || any(referenceEnergy <= 0)
    error('Local ground-truth energy is invalid.');
end

semiSimulatedData = cell(1, numel(simParams.targetSnrDbValues));

for snrIdx = 1:numel(simParams.targetSnrDbValues)

    targetSnrDb = simParams.targetSnrDbValues(snrIdx);
    snrLin = 10^(targetSnrDb / 10);

    if ~isfinite(snrLin) || snrLin <= 0
        error('Invalid target SNR %.6f dB.', targetSnrDb);
    end

    contaminatedData = cleanData;

    for k = 1:numel(insertSamples)
        idx = insertSamples(k):artifactEndSamples(k);

        % Compute one scaling coefficient for each artifact occurrence from
        % the ground-truth EEG samples in the corresponding insertion window.
        scaleFactor = sqrt(referenceEnergy(k) / (snrLin * artifactEnergy));

        artifactScaled = artifactData * scaleFactor;
        contaminatedData(:, idx) = contaminatedData(:, idx) + artifactScaled;
    end

    semiSimulatedData{snrIdx} = contaminatedData;
end

end
