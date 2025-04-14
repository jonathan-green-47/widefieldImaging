function map = french(n, cMin, cMax)
% map = french(n, cMin, cMax) creates a blue-white-red colormap with zero
% being white.

if nargin < 1
    n = 100;
end
if nargin < 2
    cMin = min(get(gca, 'clim'));
end
if nargin < 3
    cMax = max(get(gca, 'clim'));
end

if n<5
    error('N must be >=5')
end
if cMin>=cMax
    error('min must be < max')
end

maxLim = max(abs([cMin, cMax]));

x = [-maxLim, 0, maxLim];
xq = linspace(cMin, cMax, n);

% red = interp1(x, [0.1 0.7 0.9], xq, 'linear', 'extrap');
% green = interp1(x, [0.1 0.7 0.1], xq, 'linear',  'extrap');
% blue = interp1(x, [0.9 0.7 0.1], xq, 'linear',  'extrap');

red = interp1(x,   [0.1 0.9 0.9], xq, 'linear', 'extrap');
green = interp1(x, [0.1 0.9 0.1], xq, 'linear',  'extrap');
blue = interp1(x,  [0.9 0.9 0.1], xq, 'linear',  'extrap');

map = cat(2, red(:), green(:), blue(:));




% This old code mapped two separate color slopes above and below zero, so
% that there would always be both fully saturated red and blue on the map:

% % If min, max don't include zero, we have to stretch the map:
% nInterp = round(n*max(range([cMin, cMax]), max(abs([cMin, cMax])))/range([cMin, cMax]));
% cMinStretched = min(cMin, 0);
% cMaxStretched = max(cMax, 0);
% 
% % Stretch map so that it has the same slope on both sides:
% limit = max(abs([cMinStretched, cMaxStretched]));
% cMinStretched = sign(cMinStretched) * limit;
% cMaxStretched = sign(cMaxStretched) * limit;
% 
% x = sort([cMinStretched+eps, cMaxStretched-eps, 0]); % Eps in case min or max is zero;
% xq = linspace(cMinStretched, cMaxStretched, nInterp);
% 
% red = interp1(x, [0 1 1], xq, 'linear', 'extrap');
% green = interp1(x, [0 1 0], xq, 'linear',  'extrap');
% blue = interp1(x, [1 1 0], xq, 'linear',  'extrap');
% 
% map = cat(2, red(:), green(:), blue(:));
% 
% % Now we have to take the part of the map that includes the region between
% % min and max (in case this region does not include 0):
% if cMinStretched == cMin
%     map = map(1:n, :);
% else
%     map = map(end-n+1:end, :);
% end
% 
% % Make sure bounds are honored:
% map = min(max(map, 0), 1);