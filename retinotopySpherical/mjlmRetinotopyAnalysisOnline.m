function dat = mjlmRetinotopyAnalysisOnline

% warning('Remember to start prefetching function in a separate Matlab instance.')
dbstop if error % In case anything fails before saving.

%% Settings:

mouseName = 'JG783';
dateStr = '250410';
nBinTemp = 1; % How much movie was binned during preprocessing.

% widefieldBase = '\\research.files.med.harvard.edu\Neurobio\HarveyLab\Matthias\data\imaging\widefield';
% widefieldBase = '\\intrinsicScope\E\Data\Matthias';
widefieldBase = 'D:\Data\Jonathan\';
%   widefieldBase = 'D:\Data\Dan\';

%widefieldBase = '\\research.files.med.harvard.edu\Neurobio\HarveyLab\Tier1\Jonathan\Behavior_Imaging_Data\Widefield';
datFolder = fullfile(widefieldBase, mouseName, [mouseName '_' dateStr '_retino']);
movFolder = fullfile(datFolder, 'mov');

ls = dir(fullfile(datFolder, ['*_retinotopy_' mouseName '.mat']));
if numel(ls) ~=1
    error('Found either none or several dat files. Check!')
end
datFile = fullfile(datFolder, ls.name);

isMotionCorrect = false;
spatialDownsamplingFactor = 1;

%% Get movie metadata:
dat = load(datFile);

% Extract numbers from file name and sort accordingly:
p = fullfile(movFolder, '*.tiff');
list = sort(strsplit(regexprep(evalc('dir(p)'), '\s{2,}', '\n'), '\n')); % Sort is necessary because evalc is not sorted alphabetically.
list = list(3:end); % Remove current and parent dir, which are not removed when using evalc.

if isempty(list)
    % This is a session where images have been pre-processed in matlab:
    isPreprocessed = true;
    p = fullfile(movFolder, '*.mat');
    list = sort(strsplit(regexprep(evalc('dir(p)'), '\s{2,}', '\n'), '\n')); % Sort is necessary because evalc is not sorted alphabetically.
    list = list(3:end); % Remove current and parent dir, which are not removed when using evalc.
else
    isPreprocessed = false;
end

nFiles = numel(list);
lst = struct;
for i = 1:nFiles
    lst(i).name = list{i};
end

cstr = regexp({lst.name}, '(?<=_)()\d+(?=\.)', 'match', 'once');
cstr(strcmp(cstr, '')) = [];
fileNameNumber = sscanf(sprintf('%s,', cstr{:}), '%d,');

[~, order] = sort(fileNameNumber);
lst = lst(order);
assert(~isempty(lst))

img = imresize(readFrame(1, movFolder, lst, isPreprocessed, nBinTemp), ...
    1/spatialDownsamplingFactor);

dat.mov.height = size(img, 1);
dat.mov.width = size(img, 2);
temporalDownSampling = 1;

%% Get condition data:
uniqueDir = unique(dat.frame.past.barDirection_deg);
nCond = numel(uniqueDir);

maxEccentricity = 70;
edges = -maxEccentricity:2:maxEccentricity;
nBins = numel(edges)-1;
edges(1) = -inf;
edges(end)=inf;

results = struct;
for iCond = 1:nCond
    results(iCond).dir = uniqueDir(iCond);
    isFrameThisCond = dat.frame.past.barDirection_deg==results(iCond).dir;
    results(iCond).nFrames = sum(isFrameThisCond);
    results(iCond).nReps = sum(abs(diff(dat.frame.past.barPosition_deg) .* isFrameThisCond(max(temporalDownSampling, 2):end))>10);
    if iCond==1
        results(iCond).nReps = results(iCond).nReps+1;
    end
    results(iCond).period = results(iCond).nFrames / results(iCond).nReps;
    results(iCond).uniqueBins = nBins;
    results(iCond).nInBin = zeros(nBins, 1); % We don't know this during online analysis and add it up later.
    results(iCond).tuning = zeros(dat.mov.height, dat.mov.width, nBins);
    results(iCond).barPosBinnedForControl = zeros(1, nBins);
    results(iCond).xShift = [];
    results(iCond).yShift = [];
end

%% Retinotopy extraction algorithm:
% Go through data frame by frame. Bin data by bar positon. Keep a running
% average for baseline subtraction.

% For motion correction, use first frame as reference, so that we can do
% analysis online: (SNR is good enough to just use one frame.)
% ref = double(imread(fullfile(movFolder, lst(1).name)));
ref = imresize(readFrame(1, movFolder, lst, isPreprocessed, nBinTemp), ...
    1/spatialDownsamplingFactor);

% Filter images for motion correction: We use a cross-shaped mask to filter
% the fourier spectrum. This has two effects: The center of the cross
% suppresses low frequencies (e.g. fluctuations due to whole image
% brightness or cortical responses). The arms of the cross suppress excess
% power at the cardinal directions from the pixel grid.
fftFiltWinH = gausswin(dat.mov.height, round(dat.mov.height/10));
fftFiltWinW = gausswin(dat.mov.width, round(dat.mov.width/10))';
fftFiltWin = bsxfun(@max, bsxfun(@rdivide, fftFiltWinH, max(fftFiltWinH)), bsxfun(@rdivide, fftFiltWinW, max(fftFiltWinW))); % Cross
ref = ifft2(ifftshift(fftshift(fft2(ref)) .* (1-fftFiltWin)));

% Pre-calculate reference FFT:
ref_fft(:,:,1) = fft2(ref);
ref_fft(:,:,2) = fftshift(ref_fft(:,:,1));
ref_fft(:,:,3) = conj(ref_fft(:,:,1));

% Break out variables for speed:
isCamTriggerFrame = dat.frame.past.isCamTriggerFrame;
barDirection_deg = dat.frame.past.barDirection_deg;
barPosition_deg = dat.frame.past.barPosition_deg;
barPosition_disc = discretize(dat.frame.past.barPosition_deg, edges);
xShift = 0;
yShift = 0;

for iCond = 1:nCond
    % Load metadat file
    dat = load(datFile);
    nStimFramesDisplayed = max(dat.frame.past.frameId);
    iFrame = 0;
    isSessionOver = 0;
    nFramesProcessedThisCond = 0;
    ticStartThisCond = tic;
    isOnline = isfield(dat.settings, 'isSessionRunning') && dat.settings.isSessionRunning;
    
    % Processing loop:
    while true
        iFrame = iFrame + 1;
        ticLoopStart = tic;
        while iFrame > nStimFramesDisplayed
            fprintf('Cond %d: Have been waiting for new frames for %1.0f seconds.\n', ...
                iCond, toc(ticLoopStart));
            
            if (toc(ticLoopStart) > 180) || ~isOnline
                % If no new data was saved for 3 minutes, assume session is
                % over:
                isSessionOver = 1;
                break
            end
            
            pause(10)
            try
                dat = load(datFile);
                % Flag indicating if session is running right now:
                isOnline = isfield(dat.settings, 'isSessionRunning') && dat.settings.isSessionRunning;
            catch err
                warning(err.Message)
                disp('Will try again in 10 seconds...')
                continue
            end
            nStimFramesDisplayed = max(dat.frame.past.frameId);
        end
        
        if isSessionOver
            break
        end
        
        % Skip the stimulus frames on which no image was triggered:
        if ~isCamTriggerFrame(iFrame)
            continue
        end
        
        % Skip frames according to temporal binning:
        if mod(iFrame, nBinTemp)~=0
            continue
        end
        
        % Skip frames that are not the right condition:
        if barDirection_deg(iFrame)~=results(iCond).dir
            tmp = barDirection_deg;
            tmp(1:iFrame) = nan;
            tmp = find(tmp==results(iCond).dir, 1, 'first')-1;
            
            if isempty(tmp)
                % No more frames of this condition:
                fprintf('No more frames for cond %d. Going to next cond.\n', ...
                    iCond, iFrame);
                break
            else
                iFrame = tmp;
                fprintf('Skipped ahead to next block of cond %d (frame %d)\n', ...
                    iCond, iFrame);
                continue
            end
        end
        
        % Load frame:
        iFile = sum(isCamTriggerFrame(1:iFrame));
        imgHere = readFrame(iFile/nBinTemp, movFolder, lst, isPreprocessed, nBinTemp);
        
        % When there are no more files, readFrame returns an empty array:
        if isempty(imgHere)
            break
        end
        
        imgHere = imresize(imgHere, spatialDownsamplingFactor);
        
        % Motion correction:
        if isMotionCorrect
            % Pre-correct with previous shift:
            xShiftPrev = xShift;
            yShiftPrev = yShift;
            imgHere = interp2(imgHere, (1:size(imgHere, 2))-xShiftPrev, ...
                                       ((1:size(imgHere, 1))-yShiftPrev)', 'cubic', 0);

            imgHereMc = ifft2(ifftshift(fftshift(fft2(imgHere)) .* (1-fftFiltWin))); % Filter image as described above (where ref is calculated).
            [imgHere, xShift, yShift] = correct_translation_singleframe(imgHereMc, ...
                ref_fft, 1, imgHere);
            
            xShift = xShift + xShiftPrev;
            results(iCond).xShift(iFrame) = xShift;
            yShift = yShift + yShiftPrev;
            results(iCond).yShift(iFrame) = yShift;
            
            % Discard frames with large shifts relative to the previous
            % frame because the image might be blurry:
            if sqrt((xShift-xShiftPrev)^2 + (yShift-yShiftPrev)^2) > 0.05
                disp('Skipping frame with large shift.')
                continue
            end
        else
            results(iCond).xShift(iFrame) = nan;
            results(iCond).yShift(iFrame) = nan;
        end
        
        % Add current frame to the appropriate bin:
        iBin = barPosition_disc(iFrame);
        results(iCond).tuning(:,:,iBin) = results(iCond).tuning(:,:,iBin) ...
            + imgHere;
        results(iCond).nInBin(iBin) = results(iCond).nInBin(iBin)+1;
        results(iCond).barPosBinnedForControl(iBin) = ...
            results(iCond).barPosBinnedForControl(iBin) + ...
            barPosition_deg(iFrame);
        
        if ~mod(nFramesProcessedThisCond, 100)
            fprintf('Cond %d: Processing file % 6.0f (%1.1f FPS) (shifts: %1.2f/%1.2f)\n', ...
                iCond, iFile, nFramesProcessedThisCond/toc(ticStartThisCond), ...
                results(iCond).xShift(iFrame), results(iCond).yShift(iFrame));
        end
        
        nFramesProcessedThisCond = nFramesProcessedThisCond+1;
        
        if ~mod(nFramesProcessedThisCond, 1000)
            try
                % Save intermediate movie for checking during processing:
                tuningHere = bsxfun(@rdivide, results(iCond).tuning, ...
                    permute(results(iCond).nInBin(:), [3 2 1]));
                isGoodFrame = results(iCond).nInBin > 0;
                tuningHere = tuningHere(:,:,isGoodFrame);
                tuningHere = bsxfun(@minus, tuningHere, mean(tuningHere, 3));
                tuningHere = min(max(tuningHere, -5000), 5000);
                tiffWrite(mat2gray(tuningHere)*2^16, ...
                    sprintf('tuning_cond%d.tif', ...
                    iCond), 'D:\temp');
            catch err
                warning('Error while saving intermediate result:\n%s', ...
                    err.message)
            end
            
            % For debugging, store intermediate 1000 frame blocks:
            
            %             tiffWrite(mat2gray(tuningHere)*2^16, ...
            %                 sprintf('tuning_cond%d_block%d.tif', ...
            %                 iCond, nFramesProcessedThisCond/1000), 'T:\');
            %             results(iCond).tuning = results(iCond).tuning.*0;
            %             results(iCond).nInBin = results(iCond).nInBin.*0;
            
        end
    end
end

%% Save:
[p, f, ~] = fileparts(datFile);
f = sprintf('%s_results%s', f, datestr(now, 'yymmdd'));
dat = load(datFile);
dat.results = results;
try
    save(fullfile(p, f), '-struct', 'dat');%, '-v7.3');
catch err
    throwAsWarning(err)
end