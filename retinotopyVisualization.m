%% Load data:
%pBase = 'Z:\HarveyLab\Tier1\Jonathan\Behavior_Imaging_Data\Widefield';

pBase = 'D:\Data\Jonathan';

mouse = 'JG783';
ls = dir(fullfile(pBase, mouse, [mouse '_*']));
ls = ls([ls.isdir]);

% Take most recent version of all files:
pAcq = fullfile(pBase, mouse, ls(end).name); 
lsDat = dir(fullfile(pAcq, ['*' mouse '.mat']));
lsResult = dir(fullfile(pAcq, ['*' mouse '*_results*.mat']));
meta = load(fullfile(pAcq, lsDat(end).name));
load(fullfile(pAcq, lsResult(end).name));
fprintf('Loaded %s.\n', lsResult(end).name);

% Check if bar position record is incorrect, i.e. flipped for 90 and 180
% degrees (this happened because I didn't take into account a rotation
% during the generation of visual stimuli):
isBarPositionSignIncorrect = meta.frame.past.barPosition_deg(...
    find(meta.frame.past.barDirection_deg == 90, 1, 'first')) < 0;


%% Get response phase:
nCond = numel(results);
conds = unique(meta.frame.past.barDirection_deg);

% Create working copy of response:
for i = 1:nCond
    results(i).tuningCorr = results(i).tuning; %#ok<*SAGROW>
    
    % Normalize by ninbin (the online analysis does not do this automatically):
    nrm = permute(nanRep(1./results(i).nInBin(:), 0), [2, 3, 1]);
    nrm(~isfinite(nrm)) = 0;
    results(i).tuningCorr = bsxfun(@times, results(i).tuningCorr, nrm);
    
    if isBarPositionSignIncorrect && (conds(i)==90 || conds(i)==180)
        results(i).tuningCorr = results(i).tuningCorr(:,:,end:-1:1);
    end
    
    results(i).isGoodFrame = results(i).nInBin>0;
    results(i).tuningCorr = results(i).tuningCorr(:,:,results(i).isGoodFrame);
end

% Smoothing:
for i = 1:nCond
    for ii = 1:size(results(i).tuningCorr, 3)
        results(i).tuningCorr(:,:,ii) = imgaussfilt(results(i).tuningCorr(:,:,ii), 4);
    end
end

for i = 1:nCond
    % Get FFT at first non-DC frequency:
    tmp = fft(results(i).tuningCorr, [], 3);

    % We multiply by -1 to rotate the complex angle by 180 deg so that the
    % center of the trial (center of visual field) corresponds to zero
    % angle:
    results(i).fft = tmp(:,:,2) * -1;
end

% Get added and subtracted phase field as described in Kalatsky and
% Stryker:
for i = 1:2
    results(i).add = results(i).fft .* results(i+2).fft;
    results(i).subt = results(i).fft ./ results(i+2).fft;
end

%% Play movies for visual inspection:
for i = 1:4
    % Remove edges, which can have extreme values due to motion correction:
    movHere = results(i).tuningCorr(10:end-10, 10:end-10, :);
    movHere = bsxfun(@minus, movHere, median(movHere, 3));
    implay(mat2gray(movHere, prctile(movHere(:), [1, 99])));
end

%% Plot
isBackwards = 0;

figure(1)
clf

subplot(2, 3, 1);
imagesc(wrapToPi(angle(results(1+2*isBackwards).fft)), [-pi pi])
colormap(gca, jet)
colorbar
axis equal
title([mouse ' Vertical condition 1'])

subplot(2, 3, 4);
imagesc(-wrapToPi(angle(results(2+2*isBackwards).fft)), [-pi pi])
colormap(gca, jet)
colorbar
axis equal
title('Horizontal condition 1')

subplot(2, 3, 2);
meanVerti = wrapToPi(angle(results(3).fft));
imagesc(meanVerti, [-pi pi])
colormap(gca, jet)
colorbar
axis equal
title('Vertical condition 2 (more positive = higher altitude)')
colorbar

subplot(2, 3, 5);
meanHori = -wrapToPi(angle(results(4).fft));
imagesc(meanHori, [-pi pi])
colormap(gca, jet)
colorbar
axis equal
title('Horizontal condition 2 (more positive = more temporal)')
colorbar

subplot(2, 3, 3);
powerCombined = abs(results(1).fft) ...
    + abs(results(3).fft) ...
    + abs(results(2).fft) ...
    + abs(results(4).fft);
imagesc(powerCombined, prctile(powerCombined(:), [0.5 99.0]))
colormap(gca, jet)
axis equal
title('Combined power')

meanVertiGrad = wrapToPi((angle(results(1).fft)+angle(results(3).fft))/2);
meanHoriGrad = wrapToPi((angle(results(2).fft)+angle(results(4).fft))/2);

subplot(2, 3, 6);
[~, Gdir1] = imgradient(meanVertiGrad);
[~, Gdir2] = imgradient(meanHoriGrad);
fieldSign = sind(Gdir1 - Gdir2);
fs = imgaussfilt(fieldSign, 6);
imagesc(fs, [-1 1])
colormap(gca, jet)
title('Field sign')
axis equal

return

%% Save field sign:
p = '\\research.files.med.harvard.edu\Neurobio\HarveyLab\Matthias\data\imaging\widefield\';
p = fullfile(p, mouse, 'map');
[~, n, ~] = fileparts(lsDat.name);
imwrite(ceil(mat2gray(fs, [-1 1])*255), jet(255), fullfile(p, [n '_fieldsign.png']))

lsVessel = dir(fullfile(pAcq, '*vessel*'));
if numel(lsVessel)>0
    copyfile(fullfile(pAcq, lsVessel.name), ...
        fullfile(p, [n '_vessel.tiff']));
end

%% Get delay:
if false
    subplot(2, 3, 6);
    h = impoly;
    isV1 = createMask(h);
    delay = angle(median(results(2).subt(isV1)))/2;
end

% delay = 0;
% delay = delay+0.1;

for i = 1:2
    results(i).angleNoDelay = angle(results(i).fft) - delay ;
end

for i = 3:4
    results(i).angleNoDelay = angle(results(i).fft) - delay;
end

% Plot after subtracting delay:
% figure(11101)
% imagesc(wrapToPi(results(2).angleNoDelay), [-pi pi])
% colormap(hsv)
% axis equal

% subplot(2, 3, 2);
meanVerti = wrapToPi(angle(results(1).fft+results(3).fft)/2);
% meanVerti = wrapToPi(results(3).angleNoDelay);
% imagesc(meanVerti, [-pi pi]/1.5)
% colormap(gca, jet)
% title('Vertical mean (more positive = higher altitude)')
% colorbar
% axis equal

% subplot(2, 3, 5);
meanHori = wrapToPi((results(2).angleNoDelay+results(4).angleNoDelay)/2);
% meanHori = wrapToPi(results(4).angleNoDelay);
% imagesc(meanHori, [-pi pi]/1.5)
% colormap(gca, jet)
% title('Horizontal mean (more positive = more temporal)')
% colorbar
% axis equal

% Note: Field sign is not affected by subtractind delay except for shift of discontinuity..
meanVertiGrad = wrapToPi((results(1).angleNoDelay+results(3).angleNoDelay)/2);
meanHoriGrad = wrapToPi((results(2).angleNoDelay+results(4).angleNoDelay)/2);

subplot(2, 3, 6);
[~, Gdir1] = imgradient(meanVertiGrad);
[~, Gdir2] = imgradient(meanHoriGrad);
fieldSign = sind(Gdir1 - Gdir2);
fs = imgaussfilt(fieldSign, 6);
imagesc(fs, [-1 1])
colormap(gca, jet)
title('Field sign')
axis equal

%% Save data:
wfDir = '\\research.files.med.harvard.edu\Neurobio\HarveyLab\Matthias\data\imaging\widefield\';
mapDir = fullfile(wfDir, 'MM104\map');
if ~exist(mapDir, 'dir')
    mkdir(mapDir);
end

fname = [meta.settings.expName '_retino'];

imInd = gray2ind(mat2gray(powerCombined), 255);
imwrite(imInd, jet(255), fullfile(mapDir, [fname, '_power.png']));

imInd = gray2ind(mat2gray(fieldSign), 255);
imwrite(imInd, jet(255), fullfile(mapDir, [fname, '_fieldSign.png']));
