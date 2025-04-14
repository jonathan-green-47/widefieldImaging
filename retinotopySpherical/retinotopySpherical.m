function retinotopySpherical
% error('get timing prediction right')
% error('Cover left eye!')
% error('Ensure that right eye can only see screen, no reflections')
% error('Interleave all conditions?')
% error('Keep iso at 0.5% like marshel')

%% User settings:
isDebug = false;
settings = struct;
settings.mouseName = char(inputdlg('Enter mouse name:'));

% Tested saving video directly to server. It works.
% settings.saveDir = 'D:\Data\Matthias';
folderName = [settings.mouseName, '_', ...
    datestr(now, 'yymmdd'), ...
    '_retino'];
% settings.saveDir = fullfile('Z:\HarveyLab\Matthias\data\imaging\widefield', ...
%     settings.mouseName, folderName);
settings.saveDir = fullfile('D:\Data\Jonathan', ...
    settings.mouseName, folderName);
clipboard('copy', fullfile(settings.saveDir, 'mov'));
if ~exist(settings.saveDir, 'dir')
    mkdir(settings.saveDir)
    mkdir(fullfile(settings.saveDir, 'mov'))
end

% 10 reps was not enough with transgenic. Try 20.
settings.nRepeats = 120; % 60 How often each direction is repeated, i.e. there will be 4 times as many sweeps. Garrett uses 6-10 times 10, so up to 100 sweeps!
settings.nRepeatsPerBlock = 10; % 10
settings.barWidth_deg = 12.5; % Marshel uses 20
settings.barSpeed_dps = 10; % Marshel uses 8.5-9.5 dps
settings.checkerWidth_deg = 1/0.08;
settings.checkerBlink_hz = 3; % Marshel uses 6n3 Hz
settings.minDistEyeToScreen_mm = 140;
settings.screenOri_xyPix = [-10, 55];
settings.pixelReductionFactor = 5; % How much the texture is downsampled...affects frame rate.
settings.fpsStim = 60; % Target display/acquisition rate. Max is 120 Hz (monitor refresh)
settings.camFrameStride = 1; % The camera takes one picture every this many frames.
settings.isBlueMonitorChannelOnly = false;
settings.isSessionRunning = true;
 
saveFileName = fullfile(settings.saveDir, ...
    [datestr(now, 'yyyymmdd_HHMMSS'), '_retinotopy_', settings.mouseName]);

% Empirical duration:
screenWidthDegTheoretical = 132.7;
screenHeightDegTheoretical = 104.5;
expDur = settings.nRepeats * ...
    4 * ... % Number of conditions/bar directions
    (screenWidthDegTheoretical+screenHeightDegTheoretical)*0.5/settings.barSpeed_dps;
button = questdlg(sprintf('Experiment will take about %1.1f minutes. Start video recording (dir is in clipboard), then click YES to start.', ...
    expDur/60));
if ~strcmp(button, 'Yes')
    return
end

%% Run this to find the screen origin:
if 0
    screenId = 1; %#ok<UNRCH>
    res = Screen('Resolution', screenId);
    while KbCheck 
    end
     
    while ~KbCheck 
        [x, y] = GetMouse(screenId);
        fprintf('Mouse pos x: %1.0f, y:%1.0f\n', x-res.width/2, y-res.height/2)
        pause(0.3) 
    end
end

%% Take snapshot of taskScheduleFun so that it can be reconstructed later:
% (display with fprintf('%s', sn.meta.fileTaskSchedule);
fid = fopen([mfilename('fullpath'), '.m'], 'rt');
settings.experimentCodeFile = fread(fid, inf, '*char');
fclose(fid);

%% Initialize DAQ and data logging
if ~isDebug
    camControl = daq.createSession('ni');
    addDigitalChannel(camControl,'Dev1','Port0/Line0:2','OutputOnly');
end

%% Initialize screen:
if numel(Screen('Screens')) > 1
    screen.id = 2;
else
    screen.id = 0;
end

res = Screen('Resolution', screen.id);

screen.width = res.width;
screen.height = res.height;
screen.hz = res.hz;
screen.diagInch = 27;
screen.pixPerMm = hypot(screen.width, screen.height)/(25.4 * screen.diagInch);
screen.isAntiAliasing = 0;

%% Initialize sync data storage:
frameStruct = struct;
frameStruct.frameId = 0;
frameStruct.flipTime_s = 0;
frameStruct.isCamTriggerFrame = 0;
frameStruct.barDirection_deg = 0;
frameStruct.barPosition_deg = 0;
frame = eventSeries(frameStruct);

%% Screen Setup
if isDebug
    Screen('Preference', 'SkipSyncTests', 2);
    Screen('Preference', 'WindowShieldingLevel', 1000 + 400); % 1000 means that mouse gets through to Windows.
    oldPriority = Priority;
else
    oldPriority = Priority(1);
%     blackOutWin = Screen('OpenWindow', 1, 0);
end
Screen('Preference', 'SkipSyncTests', 1);
Screen('Preference', 'VisualDebugLevel', 1); % Suppress white intro screen.
screen.win = PsychImaging('OpenWindow',  screen.id, 0, [], [], [], [], screen.isAntiAliasing);
load('C:\Users\GreenJonathan\Documents\GitHub\widefieldImaging\intrinsicScope_gammaTable_160725.mat')
Screen('LoadNormalizedGammaTable', screen.win, gammaTable*[1 1 1]);
screen.fullRect = Screen('Rect', screen.win);
% Set alpha blending settings (for fading to black at the end of a trial).
% GL_colormask = [0 1 1 0]; % RGBA mask to exclude red and green light.
% Screen('BlendFunction', screen.win, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_colormask);

if settings.isBlueMonitorChannelOnly
    Screen('FillRect', screen.win, [0 0 127])
else
    Screen('FillRect', screen.win, 127)
end
Screen('Flip', screen.win);
outputSingleScan(camControl,[1 1 0]) %LEDs on
pause(5); % For luminance adaptation.

%% Display and Acquisition Loop

%Draw first streen to ensure functions are all loaded:
tex = prepareSphericalBarTex(screen, settings, frame.next.barDirection_deg);
texMat = makeSphericalBar(tex, settings, 0, frame.next.barDirection_deg);
texMat = repmat(texMat, 1, 1, 3);
texMat(:,:,1:2) = 0;
texPtr = Screen('MakeTexture', screen.win, texMat);
Screen('DrawTexture', screen.win, texPtr, [], screen.fullRect);
Screen('Flip', screen.win);
Screen('Close', texPtr)
isExit = 0;

while KbCheck
end

nRepeatsDone = 0;
while (nRepeatsDone < settings.nRepeats) && ~isExit
    nRepeatsDone = nRepeatsDone + settings.nRepeatsPerBlock;
    for iCond = 1:4
        switch iCond
            case 1 % Azi forward
                frame.next.barDirection_deg = 0;
            case 2 % Alt forward
                frame.next.barDirection_deg = 90;
            case 3 % Azi backward
                frame.next.barDirection_deg = 180;
            case 4 % Alt backward
                frame.next.barDirection_deg = 270;
        end
        
        % Prepare texture and timers:
        tex = prepareSphericalBarTex(screen, settings, frame.next.barDirection_deg);
        
        % Add offscreen space so that there is a pause between when the bar
        % arrives at one edge of the screen and when it appears again on
        % the other edge. During this pause, the neural signal can decay,
        % so that we don't get a spillover from the last to the first bin.
        tex.altLimits_deg = tex.altLimits_deg + [-1 1]*settings.barSpeed_dps;
        
        repeatDuration_s = range(tex.altLimits_deg)/settings.barSpeed_dps;
        disp(repeatDuration_s)
        if frame.next.frameId == 0
            timeFirstFrame_s = Screen('Flip', screen.win, 0);
            t0 = timeFirstFrame_s;
        else
            t0 = frame.current.flipTime_s;
        end
        timeInCondition_s = 0;
        
        while timeInCondition_s < (repeatDuration_s * settings.nRepeatsPerBlock)
            
            % Draw frame:
            [texMat, frame.next.barPosition_deg] = ...
                makeSphericalBar(tex, settings, timeInCondition_s, frame.next.barDirection_deg);
                        
            if settings.isBlueMonitorChannelOnly
                texMat = repmat(texMat, 1, 1, 3);
                texMat(:,:,1:2) = 0;
            end
            texPtr = Screen('MakeTexture', screen.win, texMat);
            Screen('DrawTexture', screen.win, texPtr, [], screen.fullRect);
            
            % Advance frame:
            frame.next.frameId = frame.current.frameId + 1;
            frame.next.flipTime_s = Screen('Flip', screen.win, ...
                frame.current.flipTime_s+(0.75/settings.fpsStim));
            timeInCondition_s = frame.next.flipTime_s - t0;
            advance(frame);
            
            % Trigger camera acquisition:
            if ~isDebug && ...
                    mod(frame.current.frameId-1, settings.camFrameStride)==0
                outputSingleScan(camControl,[1 1 1]) % Trigger
                outputSingleScan(camControl,[1 1 0]) % Reset
                frame.current.isCamTriggerFrame = 1;
            else
                frame.current.isCamTriggerFrame = 0;
            end
            
            % Clean up:
            Screen('Close', texPtr)
            
            if KbCheck
                isExit = true;
                break
            end
        end
        
        % Save for online processing:
        saveMetadata(settings, screen, frame, saveFileName)
        
        if isExit
            break
        end
    end
end

%% Clean up
% Save:
settings.isSessionRunning = false;
saveMetadata(settings, screen, frame, saveFileName)

if ~isDebug
    % Close DAQ:
    outputSingleScan(camControl, [0 0 0])
    delete(camControl)
end


Priority(oldPriority);
Screen('CloseAll');
end

function saveMetadata(settings, screen, frame, saveFileName)
if ~exist(settings.saveDir, 'dir')
    mkdir(settings.saveDir);
end

mfile = fileread(which(mfilename));
save(saveFileName, 'settings', 'screen', 'frame', 'mfile')
fprintf('Retinotopy data saved at %s.\n', saveFileName)

end
