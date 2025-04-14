function widefieldComposite
mouseName = 'JG783';
dateAcq = '250410';
%baseFolder = ['Z:\HarveyLab\Tier1\Jonathan\Behavior_Imaging_Data\Widefield\',mouseName,'\'];
baseFolder = fullfile('D:\Data\Jonathan\',mouseName,'\');
dataFolder = dir([baseFolder,'*',dateAcq,'_retino']);
dataFolder = fullfile(baseFolder,dataFolder(1).name);
cd(dataFolder);
retinoResultFile = dir([dataFolder,'\*results*.mat']);
load(retinoResultFile(1).name);
cd([dataFolder,'\mov']);
wf_vessel = double(mat2gray(clipImage(squeeze(mean(loadTifDir_numFiles('*.tiff',100),3)),5)));
cd(dataFolder);
mkdir('map');
%% Get response phase:
nCond = numel(results);
% Create working copy of response:
for i = 1:nCond
    results(i).tuningCorr = results(i).tuning; %#ok<*SAGROW>
    
    % Normalize by ninbin (the online analysis does not do this automatically):
    nrm = permute(nanRep(1./results(i).nInBin(:), 0), [2, 3, 1]);
    nrm(~isfinite(nrm)) = 0;
    results(i).tuningCorr = bsxfun(@times, results(i).tuningCorr, nrm);
    
%     if isBarPositionSignIncorrect && (conds(i)==90 || conds(i)==180)
%         results(i).tuningCorr = results(i).tuningCorr(:,:,end:-1:1);
%     end
    
    results(i).isGoodFrame = results(i).nInBin>0;
    results(i).tuningCorr = results(i).tuningCorr(:,:,results(i).isGoodFrame);
end

% Smoothing:
for i = 1:nCond
    for ii = 1:size(results(i).tuningCorr, 3)
        results(i).tuningCorr(:,:,ii) = imgaussfilt(results(i).tuningCorr(:,:,ii), 3);
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


%% Plot
isBackwards = 0;

figure(1)
figure('Color', [1 1 1])
clf

subplot(2, 3, 1);
imagesc(wrapToPi(angle(results(1+2*isBackwards).fft)), [-pi pi])
colormap(gca, jet)
colorbar
axis equal
title(' Vertical condition 1')

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
fs = imgaussfilt(fieldSign, 4);
imagesc(fs, [-1 1])
colormap(gca, jet)
title('Field sign')
axis equal
%% Visualize original widefield imaging
mask = ones(size(wf_vessel,1), size(wf_vessel,2));
thresh = prctile(powerCombined(:),50);
maskInd = powerCombined(:) < thresh;
mask(maskInd) = 0;
mask = imgaussfilt(mask, 16);

fs_norm2 = floor((imgaussfilt(-fs,16)+1)*32);
fs_rgb2 = ind2rgb(fs_norm2,flipud(french(64,-1,1))).*mask; % flip red/blue to match conventional colors

alpha2 = 0.4*ones(size(fs_rgb2,1), size(fs_rgb2,2));
vessel_rgb2 = ind2rgb(floor(wf_vessel*64), gray(64));

figure(2), figure('Color', [1 1 1])
im_vessel2 = image(vessel_rgb2); hold on;
im_fs2 = image(fs_rgb2); hold on;
set(im_fs2,'AlphaData',alpha2);
axis equal
axis image;
%% save overlaid widefield (retinotopy on vessel)

saveas(gcf, fullfile(dataFolder,'map', [mouseName '_' dateAcq '_widefieldOverlay.png']));
end