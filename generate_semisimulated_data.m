%% generate_semisimulated_data.m
% Generate the semi-simulated EEG data.
%
% INPUTS
%   Raw EEG:
%     <Dataset root>/sub-*/ses-*/eeg/*_eeg.edf
%
%   Manual artifact annotations:
%     <Dataset root>/derivatives/manualAnnotations/sub-*/ses-*/eeg/
%         *_desc-manualannotation_eeg.edf
%
% OUTPUTS
%   Ground-truth and contaminated EDF+ files are created and saved under
%   cfg.OutputDerivativeRoot.
%
% IMPORTANT
%   - Data are expected at 250 Hz.
%
% REQUIREMENTS
%   - MATLAB R2026a or compatible
%   - Signal Processing Toolbox (edfinfo, edfheader, edfwrite)
%   - EEGLAB on the MATLAB path (pop_biosig, eeg_emptyset, eeg_checkset)
%
% Recommended use:
%   1) Download/unzip the dataset.
%   2) Add EEGLAB to the MATLAB path.
%   3) Set cfg.BidsRoot below.
%   4) Run this script.
clear; close all; clc;
%% EEGLAB
addpath('C:\path\to\eeglab2026.0.0');
eeglab nogui;
%% USER CONFIGURATION
cfg = struct();
% Root folder of the dataset.
cfg.BidsRoot = 'C:\path\to\WEEG-ARTS';
% Use a separate derivative by default so the published derivative is not
% overwritten. Set the final folder name to 'semiSimulated' only when working
% on a copy and an exact replacement is intended.
cfg.OutputDerivativeRoot = fullfile(cfg.BidsRoot, 'derivatives', 'semiSimulated_regenerated');
% Empty = discover and process every available sub-* participant.
% Example: {'sub-01','sub-02'}
cfg.Subjects = {};
% Devices: {'dev1'}, {'dev2'}, or {'dev1','dev2'}.
cfg.Devices = {'dev1','dev2'};
% EEG Device 1 acquisition configurations.
cfg.Dev1Acquisitions = {'dry','wet'};
% Artifact sessions and runs.
cfg.ArtifactSessionNumbers = [1 2];
cfg.RunNumbers = [1 2 3];
% Sampling frequency used in the semi-simulation pipeline.
cfg.SamplingFrequency = 250;
% Protect existing outputs unless explicitly enabled.
cfg.OverwriteExisting = false;
% Honor derivative_status=excluded in sub-*_sessions.tsv when available.
cfg.HonorDerivativeStatus = true;
%% SEMI-SIMULATION PARAMETERS
P = struct();
P.fsToleranceHz = 1e-6;
P.baselineStartMarker = '201';
P.baselineEndMarker = '202';
% Switch artifact: retain only the first 2 s of the manually isolated segment.
P.switchArtifactMaxSec = 2.0;
% Target SNR values applied locally to each artifact insertion window.
P.targetSnrDbValues = -5:1:5;
% Artifact isolation: zero-pad outside the manual interval, apply a 5-point
% moving average to the full zero-padded trace, then re-extract the interval.
P.artifactSmoothSpanSamples = 5;
P.artifactSmoothMethod = 'moving';
P.removeArtifactDc = false;

%% REQUIREMENT CHECKS
if ~isfolder(cfg.BidsRoot)
    error('Dataset root not found: %s', cfg.BidsRoot);
end
manualRoot = fullfile(cfg.BidsRoot, 'derivatives', 'manualAnnotations');
if ~isfolder(manualRoot)
    error('Manual-annotation derivative not found: %s', manualRoot);
end
requiredMatlabFunctions = {'edfinfo','edfheader','edfwrite'};
for i = 1:numel(requiredMatlabFunctions)
    if exist(requiredMatlabFunctions{i}, 'file') ~= 2
        error('Required MATLAB function not found: %s', requiredMatlabFunctions{i});
    end
end
if exist('pop_biosig', 'file') ~= 2 || ...
   exist('eeg_emptyset', 'file') ~= 2 || ...
   exist('eeg_checkset', 'file') ~= 2
    error(['EEGLAB is required. Add EEGLAB to the MATLAB path before ', ...
           'running this script.']);
end
eeglab nogui;
if ~isfolder(cfg.OutputDerivativeRoot)
    mkdir(cfg.OutputDerivativeRoot);
end
%% DATASET DEFINITIONS
% Artifact marker definitions.
artifactRows = {
    'ALL', 'Zygomaticus_Bilateral',       '1620', '1621';
    'ALL', 'Orbicularis_Oris',            '2120', '2121';
    'ALL', 'Eye_Movement_Vertical',       '2620', '2621';
    'ALL', 'Limb_Movement',               '2320', '2321';
    'ALL', 'Head_Movement_Horizontal',    '1320', '1321';
    'ALL', 'Deep_Breathings',             '2520', '2523';
    'ALL', 'Eye_Movement_Horizontal',     '1720', '1721';
    'ALL', 'Masseter_Temporalis',         '1420', '1421';
    'ALL', 'Head_Movement_Vertical',      '1520', '1521';
    'ALL', 'Switch_Artifact',             '1020', '1021';
    'ALL', 'Orbicularis_Oculi',           '1820', '1821';
    'ALL', 'Frontalis',                   '2420', '2421';
    'ALL', 'Corrugator',                  '1120', '1121';
    'ALL', 'Body_Movement',               '1920', '1921';
    'ALL', 'Electrode_Displacement',      '2020', '2021';
    'ALL', 'Tongue_and_Sublingual',       '2220', '2221';
    'ALL', 'Eye_Blink',                   '1220', '1221'};
% Return selected participants or discover all sub-* folders.
if ~isempty(cfg.Subjects)
    subjectList = cellstr(string(cfg.Subjects));
else
    D = dir(fullfile(cfg.BidsRoot, 'sub-*'));
    D = D([D.isdir]);
    subjectList = sort({D.name});
    if isempty(subjectList)
        error('No sub-* participant folders found under %s.', cfg.BidsRoot);
    end
end
fprintf('\nSemi-simulated data generation\n');
fprintf('Dataset root: %s\n', cfg.BidsRoot);
fprintf('Output:    %s\n', cfg.OutputDerivativeRoot);
fprintf('Subjects:  %d\n', numel(subjectList));
%% MAIN LOOP
for iSub = 1:numel(subjectList)
    bidsSub = subjectList{iSub};
    fprintf('\n============================================================\n');
    fprintf('Participant: %s\n', bidsSub);
    fprintf('============================================================\n');
    for iDev = 1:numel(cfg.Devices)
        deviceId = lower(string(cfg.Devices{iDev}));
        % Dataset-specific BIDS session conventions.
        S = struct();
        switch deviceId
            case "dev1"
                S.baselineSession = 'ses-dev1baseline';
                S.acquisitions = cfg.Dev1Acquisitions;
            case "dev2"
                S.baselineSession = 'ses-dev2baseline';
                S.acquisitions = {''};
            otherwise
                error('Unknown device: %s', deviceId);
        end
        % Read derivative_status from the participant sessions.tsv when available.
        derivativeExcluded = false;
        if cfg.HonorDerivativeStatus
            sessionsFile = fullfile(cfg.BidsRoot, bidsSub, [bidsSub '_sessions.tsv']);
            if isfile(sessionsFile)
                T = readtable( ...
                    sessionsFile, ...
                    'FileType', 'text', ...
                    'Delimiter', '\t', ...
                    'TextType', 'string', ...
                    'VariableNamingRule', 'preserve');
                required = {'session_id','derivative_status'};
                if all(ismember(required, T.Properties.VariableNames))
                    idxSession = strcmp(string(T.session_id), S.baselineSession);
                    if any(idxSession)
                        status = lower(strtrim(string(T.derivative_status(idxSession))));
                        derivativeExcluded = any(status == "excluded");
                    end
                end
            end
        end
        if derivativeExcluded
            fprintf('Skipping %s / %s: derivative_status=excluded.\n', ...
                bidsSub, deviceId);
            continue;
        end
        for iAcq = 1:numel(S.acquisitions)
            acqLabel = S.acquisitions{iAcq};
            % Build the exact raw baseline EEG path.
            baselinePrefix = sprintf('%s_%s_task-rest', ...
                bidsSub, S.baselineSession);
            if ~isempty(acqLabel)
                baselinePrefix = sprintf('%s_acq-%s', baselinePrefix, acqLabel);
            end
            baselineEdf = fullfile(cfg.BidsRoot, bidsSub, S.baselineSession, 'eeg', ...
                [baselinePrefix '_eeg.edf']);
            if ~isfile(baselineEdf)
                error('Baseline EEG not found: %s', baselineEdf);
            end
            excludedSeconds = getExcludedBaselineSeconds(bidsSub, deviceId, acqLabel);
            fprintf('\n%s | %s', bidsSub, deviceId);
            if ~isempty(acqLabel)
                fprintf(' | acq-%s', acqLabel);
            end
            fprintf('\n');
            % Create the clean ground-truth segment
            % Create the clean ground-truth segment once for the current
            % participant/device/acquisition.
            % Build the ground truth from the raw baseline EEG.
            %
            % Excluded seconds refer to the beginning of the full baseline recording.
            % Each [s,s+1] interval is converted to trace samples and intersected with
            % the EEG segment delimited by markers 201 and 202.
            EEGbase = loadBidsEegDataset( ...
                baselineEdf, bidsSub, 'baseline', ...
                [bidsSub '_baseline'], cfg.SamplingFrequency, P.fsToleranceHz);
            [baselineStartSample, baselineEndSample] = findMarkerWindow( ...
                EEGbase, P.baselineStartMarker, P.baselineEndMarker);
            baselineRawFull = double( ...
                EEGbase.data(:, baselineStartSample:baselineEndSample));
            Fs = double(EEGbase.srate);
            baseLabels = string({EEGbase.chanlocs.labels});
            nBaseSamples = size(baselineRawFull, 2);
            baselineEndSampleInTrace = baselineStartSample + nBaseSamples - 1;
            badRangesInBaseline = zeros(0, 2);
            for i = 1:numel(excludedSeconds)
                badStartTrace = round(excludedSeconds(i) * Fs) + 1;
                badEndTrace = round((excludedSeconds(i) + 1) * Fs);
                overlapStartTrace = max(badStartTrace, baselineStartSample);
                overlapEndTrace = min(badEndTrace, baselineEndSampleInTrace);
                if overlapStartTrace > overlapEndTrace
                    error(['Excluded interval %.0f-%.0f s does not overlap the ', ...
                        '201-202 baseline interval in %s.'], ...
                        excludedSeconds(i), excludedSeconds(i) + 1, baselineEdf);
                end
                badRangesInBaseline(end+1, :) = [ ...
                    overlapStartTrace - baselineStartSample + 1, ...
                    overlapEndTrace - baselineStartSample + 1]; 
            end
            % Merge overlapping or adjacent sample ranges.
            if ~isempty(badRangesInBaseline)
                badRangesInBaseline = sortrows(badRangesInBaseline, 1);
                mergedRanges = badRangesInBaseline(1, :);
                for i = 2:size(badRangesInBaseline, 1)
                    if badRangesInBaseline(i, 1) <= mergedRanges(end, 2) + 1
                        mergedRanges(end, 2) = max( ...
                            mergedRanges(end, 2), badRangesInBaseline(i, 2));
                    else
                        mergedRanges(end+1, :) = badRangesInBaseline(i, :); 
                    end
                end
                badRangesInBaseline = mergedRanges;
            end
            % Return the complement of badRanges over samples 1:nSamples.
            if isempty(badRangesInBaseline)
                goodRanges = [1, nBaseSamples];
            else
                goodRanges = zeros(0, 2);
                nextStart = 1;
                for i = 1:size(badRangesInBaseline, 1)
                    if nextStart <= badRangesInBaseline(i, 1) - 1
                        goodRanges(end+1, :) = [nextStart, badRangesInBaseline(i, 1) - 1]; 
                    end
                    nextStart = badRangesInBaseline(i, 2) + 1;
                end
                if nextStart <= nBaseSamples
                    goodRanges(end+1, :) = [nextStart, nBaseSamples];
                end
            end
            if isempty(goodRanges)
                error('No clean baseline samples remain for %s.', bidsSub);
            end
            % Longest contiguous clean interval = ground truth.
            goodLengths = goodRanges(:, 2) - goodRanges(:, 1) + 1;
            [~, idxLongest] = max(goodLengths);
            groundTruthRange = goodRanges(idxLongest, :);
            groundTruthData = baselineRawFull(:, groundTruthRange(1):groundTruthRange(2));
            groundTruthLen = size(groundTruthData, 2);
            % Final insertion rule used in the semi-simulation pipeline.
            if groundTruthLen > round(10 * Fs)
                manualInsertSeconds = [1 6];
            elseif groundTruthLen >= round(10 * Fs)
                manualInsertSeconds = [0 5];
            else
                manualInsertSeconds = 1;
            end
            fprintf(['Ground truth: %.2f s | insertion times: %s s | ', ...
                'excluded intervals: %d\n'], ...
                groundTruthLen / Fs, mat2str(manualInsertSeconds), ...
                numel(excludedSeconds));
            % Save the BIDS-named ground-truth EDF+.
            bidsSes = S.baselineSession;
            outDir = fullfile(cfg.OutputDerivativeRoot, bidsSub, bidsSes, 'eeg');
            if ~isfolder(outDir)
                mkdir(outDir);
            end
            prefix = sprintf('%s_%s_task-rest', bidsSub, bidsSes);
            if ~isempty(acqLabel)
                prefix = sprintf('%s_acq-%s', prefix, acqLabel);
            end
            prefix = sprintf('%s_desc-groundtruth', prefix);
            edfPath = fullfile(outDir, [prefix '_eeg.edf']);
            if isfile(edfPath) && ~cfg.OverwriteExisting
                error(['Output already exists:\n%s\nSet cfg.OverwriteExisting=true ', ...
                    'or use a different cfg.OutputDerivativeRoot.'], edfPath);
            end
            EEGgt = makeDataset(groundTruthData, Fs, EEGbase.chanlocs, bidsSub, ...
                'semi-simulated ground truth', [], prefix);
            writeEDFPlus(EEGgt, edfPath);
            % Process the two artifact sessions
            for sessionNumber = cfg.ArtifactSessionNumbers
                bidsSes = sprintf('ses-%ss%02d', char(deviceId), sessionNumber);
                % Load manually annotated runs
                EEGcond = struct();
                for runIdx = cfg.RunNumbers
                    runPrefix = sprintf('%s_%s_task-artifact', bidsSub, bidsSes);
                    if ~isempty(acqLabel)
                        runPrefix = sprintf('%s_acq-%s', runPrefix, acqLabel);
                    end
                    runPrefix = sprintf( ...
                        '%s_run-%02d_desc-manualannotation', runPrefix, runIdx);
                    manualEdfPath = fullfile(cfg.BidsRoot, 'derivatives', 'manualAnnotations', ...
                        bidsSub, bidsSes, 'eeg', [runPrefix '_eeg.edf']);
                    if ~isfile(manualEdfPath)
                        error('Manual annotation file not found: %s', manualEdfPath);
                    end
                    EEGtmp = loadBidsEegDataset(manualEdfPath, bidsSub, bidsSes, ...
                        sprintf('%s_%s_run-%02d_manual', bidsSub, bidsSes, runIdx), ...
                        Fs, P.fsToleranceHz);
                    condLabels = string({EEGtmp.chanlocs.labels});
                    [hasAllChannels, reorderIdx] = ismember(baseLabels, condLabels);
                    if ~all(hasAllChannels)
                        missing = baseLabels(~hasAllChannels);
                        error('Dataset %s is missing baseline channels: %s', ...
                            manualEdfPath, strjoin(missing, ', '));
                    end
                    EEGtmp.data = EEGtmp.data(reorderIdx, :);
                    EEGtmp.nbchan = size(EEGtmp.data, 1);
                    EEGtmp.chanlocs = EEGtmp.chanlocs(reorderIdx);
                    EEGtmp = eeg_checkset(EEGtmp);
                    fieldName = sprintf('run_%02d', runIdx);
                    EEGcond.(fieldName) = EEGtmp;
                end
                if isempty(fieldnames(EEGcond))
                    error('No manually annotated runs found for %s / %s.', ...
                        bidsSub, bidsSes);
                end
                artifactInstances = collectArtifactInstancesFromRuns( ...
                    EEGcond, artifactRows, Fs);
                if isempty(artifactInstances)
                    error('No manual artifact windows found for %s / %s.', ...
                        bidsSub, bidsSes);
                end
                % Create contaminated outputs
                outDir = fullfile(cfg.OutputDerivativeRoot, bidsSub, bidsSes, 'eeg');
                if ~isfolder(outDir)
                    mkdir(outDir);
                end
                usedPrefixes = strings(0,1);
                for a = 1:numel(artifactInstances)
                    sourceRunName = artifactInstances(a).run;
                    artifactName = artifactInstances(a).artifact_name;
                    markerOn = artifactInstances(a).manual_marker_on;
                    markerOff = artifactInstances(a).manual_marker_off;
                    EEGart = EEGcond.(sourceRunName);
                    artifactStartSample = artifactInstances(a).manual_start_sample;
                    artifactEndSample = artifactInstances(a).manual_end_sample;
                    % Dataset-specific rule: for Switch Artifact, only the first 2 s
                    % of the isolated and smoothed artifact segment are retained.
                    maxArtifactDurationSec = Inf;
                    if strcmp(artifactName, 'Switch_Artifact')
                        maxArtifactDurationSec = P.switchArtifactMaxSec;
                    end
                    % Parameters passed to the general semi-simulation function.
                    simParams = struct();
                    simParams.targetSnrDbValues = P.targetSnrDbValues;
                    simParams.insertSeconds = manualInsertSeconds;
                    simParams.smoothSpanSamples = P.artifactSmoothSpanSamples;
                    simParams.smoothMethod = P.artifactSmoothMethod;
                    simParams.removeArtifactDc = P.removeArtifactDc;
                    simParams.maxArtifactDurationSec = maxArtifactDurationSec;
                    % Generate the semi-simulated EEG signals.
                    [semiSimulatedData, artifactPositions] = createSemiSimulatedEEG( ...
                        groundTruthData, double(EEGart.data), ...
                        artifactStartSample, artifactEndSample, Fs, simParams);
                    % Create one start/end marker pair for every inserted artifact occurrence.
                    eventStruct = struct('type', {}, 'latency', {}, 'duration', {});
                    for k = 1:size(artifactPositions, 1)
                        eventStruct(end+1).type = char(markerOn); 
                        eventStruct(end).latency = artifactPositions(k, 1);
                        eventStruct(end).duration = 0;
                        eventStruct(end+1).type = char(markerOff); 
                        eventStruct(end).latency = artifactPositions(k, 2);
                        eventStruct(end).duration = 0;
                    end
                    for snrIdx = 1:numel(P.targetSnrDbValues)
                        targetSnrDb = P.targetSnrDbValues(snrIdx);
                        contaminatedData = semiSimulatedData{snrIdx};
                        % Match the desc naming convention.
                        % Example: Eye_Blink, -5 dB -> eyeblinksnrm5db.
                        artLabel = erase(lower(string(artifactName)), '_');
                        if targetSnrDb < 0
                            snrLabel = sprintf('m%ddb', abs(round(targetSnrDb)));
                        else
                            snrLabel = sprintf('p%ddb', round(targetSnrDb));
                        end
                        descLabel = char(artLabel + "snr" + string(snrLabel));
                        prefix = sprintf('%s_%s_task-artifact', bidsSub, bidsSes);
                        if ~isempty(acqLabel)
                            prefix = sprintf('%s_acq-%s', prefix, acqLabel);
                        end
                        prefix = sprintf('%s_desc-%s', prefix, descLabel);
                        if any(usedPrefixes == string(prefix))
                            error(['Output collision for %s. More than one manual instance ', ...
                                'of the same artifact source was found in the same session.'], ...
                                prefix);
                        end
                        usedPrefixes(end+1,1) = string(prefix); 
                        EEGcont = makeDataset( ...
                            contaminatedData, Fs, EEGbase.chanlocs, bidsSub, ...
                            'semi-simulated contaminated EEG', eventStruct, prefix);
                        edfPath = fullfile(outDir, [prefix '_eeg.edf']);
                        if isfile(edfPath) && ~cfg.OverwriteExisting
                            error(['Output already exists:\n%s\nSet cfg.OverwriteExisting=true ', ...
                                'or use a different cfg.OutputDerivativeRoot.'], edfPath);
                        end
                        writeEDFPlus(EEGcont, edfPath);
                        fprintf('Created: %s | %s | SNR %+d dB\n', ...
                            bidsSes, artifactName, targetSnrDb);
                    end
                end
            end
        end
    end
end
fprintf('\n============================================================\n');
fprintf('Semi-simulated generation completed.\n');
fprintf('Output derivative:\n%s\n', cfg.OutputDerivativeRoot);
fprintf('============================================================\n');
%% LOCAL FUNCTIONS
function artifactInstances = collectArtifactInstancesFromRuns( ...
    EEGcond, artifactRows, Fs)
% Scan all manually annotated runs and collect the manual artifact windows.
    artifactInstances = struct( ...
        'run', {}, ...
        'artifact_name', {}, ...
        'original_marker_on', {}, ...
        'original_marker_off', {}, ...
        'manual_marker_on', {}, ...
        'manual_marker_off', {}, ...
        'manual_start_sample', {}, ...
        'manual_end_sample', {}, ...
        'source_start_sample', {}, ...
        'source_end_sample', {}, ...
        'duration_sec', {}, ...
        'occurrence_index', {});
    runs = fieldnames(EEGcond);
    for rRun = 1:numel(runs)
        runName = runs{rRun};
        EEG = EEGcond.(runName);
        [eventTypes, eventLatencies] = getEventTypesAndLatencies(EEG.event);
        for r = 1:size(artifactRows, 1)
            artifactName = char(artifactRows{r, 2});
            originalMarkerOn = char(artifactRows{r, 3});
            originalMarkerOff = char(artifactRows{r, 4});
            manualMarkerOn = [originalMarkerOn '1'];
            manualMarkerOff = [originalMarkerOff '1'];
            manualPairs = pairEventWindows( ...
                eventTypes, eventLatencies, ...
                manualMarkerOn, manualMarkerOff, EEG.pnts);
            if isempty(manualPairs)
                continue;
            end
            originalPairs = pairEventWindows( ...
                eventTypes, eventLatencies, ...
                originalMarkerOn, originalMarkerOff, EEG.pnts);
            for k = 1:size(manualPairs, 1)
                manualStart = manualPairs(k, 1);
                manualEnd = manualPairs(k, 2);
                sourceStart = NaN;
                sourceEnd = NaN;
                if ~isempty(originalPairs)
                    containingOriginal = find( ...
                        originalPairs(:, 1) <= manualStart & ...
                        originalPairs(:, 2) >= manualEnd, 1, 'first');
                    if isempty(containingOriginal)
                        containingOriginal = find( ...
                            originalPairs(:, 1) <= manualStart, 1, 'last');
                    end
                    if ~isempty(containingOriginal)
                        sourceStart = originalPairs(containingOriginal, 1);
                        sourceEnd = originalPairs(containingOriginal, 2);
                    end
                end
                artifactInstances(end+1).run = runName; 
                artifactInstances(end).artifact_name = artifactName;
                artifactInstances(end).original_marker_on = originalMarkerOn;
                artifactInstances(end).original_marker_off = originalMarkerOff;
                artifactInstances(end).manual_marker_on = manualMarkerOn;
                artifactInstances(end).manual_marker_off = manualMarkerOff;
                artifactInstances(end).manual_start_sample = manualStart;
                artifactInstances(end).manual_end_sample = manualEnd;
                artifactInstances(end).source_start_sample = sourceStart;
                artifactInstances(end).source_end_sample = sourceEnd;
                artifactInstances(end).duration_sec = (manualEnd - manualStart + 1) / Fs;
                artifactInstances(end).occurrence_index = k;
            end
        end
    end
    if ~isempty(artifactInstances)
        sortKeys = strings(numel(artifactInstances), 1);
        for i = 1:numel(artifactInstances)
            sortKeys(i) = sprintf('%s_%012d_%s', ...
                artifactInstances(i).run, ...
                artifactInstances(i).manual_start_sample, ...
                artifactInstances(i).artifact_name);
        end
        [~, order] = sort(sortKeys);
        artifactInstances = artifactInstances(order);
    end
end
function pairs = pairEventWindows( ...
    eventTypes, eventLatencies, startType, endType, nSamples)
    % Pair each start marker with the next unused later end marker.
    startIdx = find(strcmp(eventTypes, startType));
    endIdx = find(strcmp(eventTypes, endType));
    pairs = zeros(0, 2);
    if isempty(startIdx) || isempty(endIdx)
        return;
    end
    [~, startOrder] = sort(eventLatencies(startIdx));
    startIdx = startIdx(startOrder);
    [~, endOrder] = sort(eventLatencies(endIdx));
    endIdx = endIdx(endOrder);
    usedEnd = false(size(endIdx));
    for i = 1:numel(startIdx)
        startSample = round(eventLatencies(startIdx(i)));
        availableEnd = find( ...
            ~usedEnd & eventLatencies(endIdx) > startSample, ...
            1, 'first');
        if isempty(availableEnd)
            continue;
        end
        usedEnd(availableEnd) = true;
        endSample = round(eventLatencies(endIdx(availableEnd)));
        startSample = max(1, min(nSamples, startSample));
        endSample = max(1, min(nSamples, endSample));
        if endSample > startSample
            pairs(end+1, :) = [startSample, endSample]; 
        end
    end
end
function badSeconds = getExcludedBaselineSeconds( ...
    bidsSub, deviceId, acqLabel)
    % Convert sub-01 -> 1 and validate the participant range.
    token = regexp(bidsSub, '^sub-(\d+)$', 'tokens', 'once');
    if isempty(token)
        error('Invalid BIDS participant label: %s', bidsSub);
    end
    idx = str2double(token{1});
    if ~isfinite(idx) || idx < 1 || idx > 21 || idx ~= round(idx)
        error('Participant index must be between 1 and 21: %s', bidsSub);
    end
    switch lower(string(deviceId))
        case "dev1"
            if strcmpi(acqLabel, 'dry')
                T = cell(21,1);
                T{1}  = [21 22 23 55 56];
                T{2}  = [20 57];
                T{3}  = [20 21 33 34 50 54 55 59 60];
                T{4}  = [20 22 28 51 52];
                T{5}  = [41 42];
                T{6}  = [20 24 44 45];
                T{7}  = [22 23 47];
                T{8}  = [20 37 38 39 42 43];
                T{9}  = [20 23 24 25 26 27 29 30 31 37];
                T{10} = [];
                T{11} = [];
                T{12} = [43 44];
                T{13} = [35 36 52 53];
                T{14} = [36 37 38 39 55 56 57 58 59 60];
                T{15} = [];
                T{16} = [20 24 25 33 34 37 46 47 48];
                T{17} = [20 28 31 33 44 58];
                T{18} = [28 31 38 39 40 41 43];
                T{19} = [20 39 41 42];
                T{20} = 24;
                T{21} = [21 29 33 49 50 55 60];
            elseif strcmpi(acqLabel, 'wet')
                T = cell(21,1);
                T{1}  = [];
                T{2}  = [];
                T{3}  = [20 32 33 44 45];
                T{4}  = [20 41 42 45 54 55];
                T{5}  = [21 34 48 49];
                T{6}  = [35 36 37 38];
                T{7}  = 56;
                T{8}  = [20 37 38];
                T{9}  = [20 24 25 37];
                T{10} = [];
                T{11} = [32 37 38 39 45 46 54 57 58];
                T{12} = [39 40 51 55 56 57 58 59 60];
                T{13} = 36;
                T{14} = [];
                T{15} = [];
                T{16} = [22 30 31 44 45 54 59 60];
                T{17} = [20 21 26 30 32 45 47];
                T{18} = [];
                T{19} = [38 39];
                T{20} = [20 21 22 23 24 37];
                T{21} = 54;
            else
                error('Device 1 acquisition must be dry or wet.');
            end
            badSeconds = T{idx};
        case "dev2"
            T = cell(21,1);
            T{1}  = [33 49 50 52 53];
            T{2}  = [21 22 31 32 33 34];
            T{3}  = [31 32 38 39 49 56 59 60 61];
            T{4}  = [34 46];
            T{5}  = [33 37 38];
            T{6}  = [];
            T{7}  = 22;
            T{8}  = [21 54 55];
            T{9}  = [];
            T{10} = [];
            T{11} = [28 48 49 59 60 61];
            T{12} = [39 41 42 43 44 45 46 47];
            T{13} = [21 52 53];
            T{14} = [24 25 26 27 35 36 54 55];
            T{15} = 49;
            T{16} = [21 28 29 30 31 41 42 43 57 60 61];
            T{17} = [25 32 33 38 43 44 45];
            T{18} = [55 56];
            T{19} = [21 23 29 39 40 49 50 51 52 58 59];
            T{20} = [];
            T{21} = [30 46];
            badSeconds = T{idx};
        otherwise
            error('Unknown device: %s', deviceId);
    end
end
function EEG = loadBidsEegDataset( ...
    edfPath, subjectName, conditionName, setName, expectedFs, toleranceHz)
% Load signal samples from EDF+ and markers from the events.tsv sidecar.
% EDF annotations are used as a fallback if the sidecar is unavailable.
    if ~isfile(edfPath)
        error('EDF file not found: %s', edfPath);
    end
    info = edfinfo(edfPath);
    dataRecordDurationSec = seconds(info.DataRecordDuration);
    fsFromHeader = double(info.NumSamples(:)) ./ dataRecordDurationSec;
    if isempty(fsFromHeader) || any(~isfinite(fsFromHeader))
        error('Invalid sampling-rate information in EDF header: %s', edfPath);
    end
    if any(abs(fsFromHeader - expectedFs) > toleranceHz)
        error(['Unexpected EDF sampling rate in %s. Expected %.12f Hz; ', ...
               'header reports %.12f-%.12f Hz. No resampling is performed.'], ...
            edfPath, expectedFs, min(fsFromHeader), max(fsFromHeader));
    end
    EEGraw = pop_biosig( ...
        edfPath, ...
        'importevent', 'off', ...
        'importannot', 'off');
    if isempty(EEGraw.data)
        error('No signal data were read from: %s', edfPath);
    end
    if EEGraw.trials ~= 1
        error('EEG dataset is not continuous: %s', edfPath);
    end
    if any(~isfinite(double(EEGraw.data(:))))
        error('EEG signal contains NaN/Inf: %s', edfPath);
    end
    if abs(double(EEGraw.srate) - expectedFs) > toleranceHz
        error('Unexpected BioSig sampling rate in: %s', edfPath);
    end
    EEG = eeg_emptyset;
    EEG.data = double(EEGraw.data);
    EEG.nbchan = size(EEG.data, 1);
    EEG.pnts = size(EEG.data, 2);
    EEG.trials = 1;
    EEG.srate = double(expectedFs);
    EEG.xmin = 0;
    EEG.xmax = (EEG.pnts - 1) / EEG.srate;
    EEG.times = (0:EEG.pnts-1) ./ EEG.srate .* 1000;
    EEG.subject = subjectName;
    EEG.condition = conditionName;
    EEG.setname = setName;
    signalLabels = string(info.SignalLabels(:)).';
    if numel(signalLabels) ~= EEG.nbchan
        signalLabels = signalLabels(1:min(numel(signalLabels), EEG.nbchan));
    end
    if numel(signalLabels) ~= EEG.nbchan
        error('EDF signal-label count does not match loaded channels: %s', edfPath);
    end
    EEG.chanlocs = struct('labels', cell(1, EEG.nbchan));
    for ch = 1:EEG.nbchan
        EEG.chanlocs(ch).labels = char(signalLabels(ch));
    end
    % Replace *_eeg.edf with *_events.tsv.
    suffix = '_eeg.edf';
    if endsWith(edfPath, suffix, 'IgnoreCase', true)
        eventsPath = [edfPath(1:end-numel(suffix)) '_events.tsv'];
    else
        [folder, stem] = fileparts(edfPath);
        eventsPath = fullfile(folder, [stem '_events.tsv']);
    end
    if isfile(eventsPath)
        % Convert events.tsv rows containing sample and marker_label to EEGLAB events.
        T = readtable( ...
            eventsPath, ...
            'FileType', 'text', ...
            'Delimiter', '\t', ...
            'TextType', 'string', ...
            'VariableNamingRule', 'preserve');
        if ~ismember('sample', T.Properties.VariableNames) || ...
           ~ismember('marker_label', T.Properties.VariableNames)
            error('Events file lacks sample/marker_label: %s', eventsPath);
        end
        if isnumeric(T.sample) || islogical(T.sample)
            samples = double(T.sample);
        else
            samples = str2double(string(T.sample));
        end
        samples = samples(:);
        labels = string(T.marker_label);
        keep = isfinite(samples) & samples >= 1 & samples <= EEG.pnts & labels ~= "";
        samples = round(samples(keep));
        labels = labels(keep);
        [samples, order] = sort(samples);
        labels = labels(order);
        EEG.event = struct('type', {}, 'latency', {}, 'duration', {});
        for i = 1:numel(samples)
            EEG.event(end+1).type = char(labels(i)); 
            EEG.event(end).latency = samples(i);
            EEG.event(end).duration = 0;
        end
    else
        % Convert EDF+ annotations to EEGLAB events.
        EEG.event = struct('type', {}, 'latency', {}, 'duration', {});
        annotations = info.Annotations;
        if ~isempty(annotations)
            for i = 1:height(annotations)
                onsetSec = seconds(annotations.Properties.RowTimes(i));
                latency = round(onsetSec * EEG.srate) + 1;
                if latency < 1 || latency > EEG.pnts
                    continue;
                end
                eventType = strtrim(char(string(annotations.Annotations(i))));
                if isempty(eventType)
                    continue;
                end
                durationSamples = 0;
                if ismember('Duration', annotations.Properties.VariableNames)
                    durationSec = seconds(annotations.Duration(i));
                    if isfinite(durationSec)
                        durationSamples = durationSec * EEG.srate;
                    end
                end
                EEG.event(end+1).type = eventType; 
                EEG.event(end).latency = latency;
                EEG.event(end).duration = durationSamples;
            end
        end
    end
    % Sort events and create standard EEGLAB urevent.
    if isempty(EEG.event)
        EEG.urevent = [];
        EEG = eeg_checkset(EEG);
    else
        if isfield(EEG.event, 'urevent')
            EEG.event = rmfield(EEG.event, 'urevent');
        end
        EEG.urevent = [];
        [~, order] = sort([EEG.event.latency]);
        EEG.event = EEG.event(order);
        EEG = eeg_checkset(EEG, 'eventconsistency');
        EEG = eeg_checkset(EEG, 'makeur');
    end
end
function [startSample, endSample] = findMarkerWindow(EEG, markerOn, markerOff)
% Return the interval between the first markerOn and first later markerOff.
    [eventTypes, eventLatencies] = getEventTypesAndLatencies(EEG.event);
    eventLatencies = round(eventLatencies);
    idxOn = find(strcmp(eventTypes, markerOn), 1, 'first');
    if isempty(idxOn)
        error('Marker %s not found in dataset %s.', markerOn, EEG.setname);
    end
    idxOffCandidates = find( ...
        strcmp(eventTypes, markerOff) & ...
        eventLatencies > eventLatencies(idxOn));
    if isempty(idxOffCandidates)
        error('Marker %s after %s not found in dataset %s.', ...
            markerOff, markerOn, EEG.setname);
    end
    idxOff = idxOffCandidates(1);
    startSample = max(1, eventLatencies(idxOn));
    endSample = min(EEG.pnts, eventLatencies(idxOff));
    if endSample <= startSample
        error('Invalid marker window %s-%s in dataset %s.', ...
            markerOn, markerOff, EEG.setname);
    end
end
function [eventTypes, eventLatencies] = getEventTypesAndLatencies(events)
% Normalize EEGLAB event fields.
    if isempty(events)
        eventTypes = {};
        eventLatencies = [];
        return;
    end
    nEvents = numel(events);
    eventTypes = cell(1, nEvents);
    eventLatencies = nan(1, nEvents);
    for e = 1:nEvents
        eventTypes{e} = eventTypeToChar(events(e).type);
        if isfield(events, 'latency') && ~isempty(events(e).latency)
            eventLatencies(e) = double(events(e).latency);
        end
    end
end
function txt = eventTypeToChar(rawType)
% Convert an EEGLAB event type to char.
    if isnumeric(rawType)
        txt = num2str(rawType);
    elseif isstring(rawType)
        txt = char(rawType);
    elseif ischar(rawType)
        txt = rawType;
    else
        txt = char(string(rawType));
    end
end
function EEGout = makeDataset( ...
    dataMatrix, Fs, chanlocs, subjectName, conditionName, events, setName)
% Build a continuous EEGLAB dataset from a channels x samples matrix.
    EEGout = eeg_emptyset;
    EEGout.data = double(dataMatrix);
    EEGout.srate = Fs;
    EEGout.nbchan = size(dataMatrix, 1);
    EEGout.pnts = size(dataMatrix, 2);
    EEGout.trials = 1;
    EEGout.xmin = 0;
    EEGout.xmax = (EEGout.pnts - 1) / Fs;
    EEGout.times = (0:EEGout.pnts-1) ./ Fs .* 1000;
    EEGout.subject = subjectName;
    EEGout.condition = conditionName;
    EEGout.setname = setName;
    EEGout.chanlocs = chanlocs;
    if isempty(events)
        EEGout.event = struct('type', {}, 'latency', {}, 'duration', {});
    else
        EEGout.event = events;
    end
    % Sort events and create standard EEGLAB urevent.
    if isempty(EEGout.event)
        EEGout.urevent = [];
        EEGout = eeg_checkset(EEGout);
    else
        if isfield(EEGout.event, 'urevent')
            EEGout.event = rmfield(EEGout.event, 'urevent');
        end
        EEGout.urevent = [];
        [~, order] = sort([EEGout.event.latency]);
        EEGout.event = EEGout.event(order);
        EEGout = eeg_checkset(EEGout, 'eventconsistency');
        EEGout = eeg_checkset(EEGout, 'makeur');
    end
end
function writeEDFPlus(EEG, edfPath)
% Write a continuous EDF+ file with EEG.event stored as true annotations.
    data = double(EEG.data).';
    nSamples = size(data, 1);
    nChannels = size(data, 2);
    if isempty(data) || nSamples < 1 || nChannels < 1
        error('Cannot write EDF+: EEG data are empty.');
    end
    if any(~isfinite(data(:)))
        error('Cannot write EDF+: signal contains NaN/Inf.');
    end
    labels = string({EEG.chanlocs.labels});
    if numel(labels) ~= nChannels
        error('Channel labels do not match EEG channels.');
    end
    if any(strlength(labels) > 16)
        error('At least one EDF signal label exceeds 16 characters.');
    end
    physicalMin = min(data(:));
    physicalMax = max(data(:));
    if physicalMin == physicalMax
        margin = max(abs(physicalMin) * 1e-6, 1e-6);
        physicalMin = physicalMin - margin;
        physicalMax = physicalMax + margin;
    end
    hdr = edfheader("EDF+");
    hdr.Patient = "X X X X";
    hdr.Recording = "Startdate X X X X";
    hdr.StartDate = "01.01.85";
    hdr.StartTime = "00.00.00";
    hdr.Reserved = "EDF+C";
    hdr.NumDataRecords = 1;
    hdr.DataRecordDuration = seconds(nSamples / double(EEG.srate));
    hdr.NumSignals = nChannels;
    hdr.SignalLabels = labels;
    hdr.TransducerTypes = repmat("", 1, nChannels);
    hdr.PhysicalDimensions = repmat("", 1, nChannels);
    hdr.PhysicalMin = repmat(physicalMin, 1, nChannels);
    hdr.PhysicalMax = repmat(physicalMax, 1, nChannels);
    hdr.DigitalMin = repmat(-32768, 1, nChannels);
    hdr.DigitalMax = repmat(32767, 1, nChannels);
    hdr.Prefilter = repmat("", 1, nChannels);
    hdr.SignalReserved = repmat("", 1, nChannels);
    if isfile(edfPath)
        delete(edfPath);
    end
    if isempty(EEG.event)
        edfwrite(edfPath, hdr, data, InputSampleType="physical");
    else
        % Convert EEGLAB events to an EDF+ annotation timetable.
        nEvents = numel(EEG.event);
        onsetSec = zeros(nEvents, 1);
        annotationText = strings(nEvents, 1);
        durationSec = zeros(nEvents, 1);
        for i = 1:nEvents
            onsetSec(i) = ...
                (double(EEG.event(i).latency) - 1) / double(EEG.srate);
            annotationText(i) = string(eventTypeToChar(EEG.event(i).type));
            if isfield(EEG.event, 'duration') && ~isempty(EEG.event(i).duration)
                durationSamples = double(EEG.event(i).duration);
                if isfinite(durationSamples)
                    durationSec(i) = durationSamples / double(EEG.srate);
                end
            end
        end
        Onset = seconds(onsetSec);
        Annotations = annotationText;
        Duration = seconds(durationSec);
        annotations = timetable(Onset, Annotations, Duration);
        edfwrite( ...
            edfPath, hdr, data, annotations, ...
            InputSampleType="physical");
    end
    if ~isfile(edfPath)
        error('EDF+ file was not created: %s', edfPath);
    end
    % Validate channel layout, sample count and annotations after writing EDF+.
    info = edfinfo(edfPath);
    if strtrim(string(info.Reserved)) ~= "EDF+C"
        error('Output file is not continuous EDF+: %s', edfPath);
    end
    if double(info.NumSignals) ~= EEG.nbchan
        error('EDF+ channel count mismatch in %s.', edfPath);
    end
    if any(double(info.NumSamples(:)) ~= EEG.pnts)
        error('EDF+ sample count mismatch in %s.', edfPath);
    end
    expectedSignalLabels = string({EEG.chanlocs.labels});
    recoveredSignalLabels = string(info.SignalLabels(:)).';
    if ~isequal(recoveredSignalLabels, expectedSignalLabels)
        error('EDF+ signal labels do not match EEG.chanlocs in %s.', edfPath);
    end
    recovered = info.Annotations;
    nEvents = numel(EEG.event);
    if height(recovered) ~= nEvents
        error('EDF+ annotation count mismatch in %s. Expected %d, found %d.', ...
            edfPath, nEvents, height(recovered));
    end
    if nEvents == 0
        return;
    end
    expectedOnset = zeros(nEvents, 1);
    expectedLabel = strings(nEvents, 1);
    for i = 1:nEvents
        expectedOnset(i) = ...
            (double(EEG.event(i).latency) - 1) / double(EEG.srate);
        expectedLabel(i) = string(eventTypeToChar(EEG.event(i).type));
    end
    recoveredOnset = seconds(recovered.Properties.RowTimes);
    recoveredLabel = string(recovered.Annotations);
    expectedTable = table(expectedOnset, expectedLabel, ...
        'VariableNames', {'Onset','Label'});
    recoveredTable = table(recoveredOnset, recoveredLabel, ...
        'VariableNames', {'Onset','Label'});
    expectedTable = sortrows(expectedTable, {'Onset','Label'});
    recoveredTable = sortrows(recoveredTable, {'Onset','Label'});
    if ~isequal(expectedTable.Label, recoveredTable.Label)
        error('EDF+ annotation labels do not match EEG.event in %s.', edfPath);
    end
    tolerance = 0.5 / double(EEG.srate) + 1e-12;
    if any(abs(expectedTable.Onset - recoveredTable.Onset) > tolerance)
        error('EDF+ annotation onsets do not match EEG.event in %s.', edfPath);
    end
end
