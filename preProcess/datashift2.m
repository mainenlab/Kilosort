function rez = datashift2(rez)

if  getOr(rez.ops, 'nblocks', 1)==0
    return;
end

ops = rez.ops;

% The min and max of the y and x ranges of the channels
ymin = min(rez.yc);
ymax = max(rez.yc);
xmin = min(rez.xc);
xmax = max(rez.xc);

% Determine the average vertical spacing between channels. 
% Usually all the vertical spacings are the same, i.e. on Neuropixels probes. 
dmin = median(diff(unique(rez.yc)));
fprintf('pitch is %d um\n', dmin)
rez.ops.yup = ymin:dmin/2:ymax; % centers of the upsampled y positions

% Determine the template spacings along the x dimension
xrange = xmax - xmin;
npt = floor(xrange/16); % this would come out as 16um for Neuropixels probes, which aligns with the geometry. 
rez.ops.xup = linspace(xmin, xmax, npt+1); % centers of the upsampled x positions

spkTh = 10; % same as the usual "template amplitude", but for the generic templates

% Extract all the spikes across the recording that are captured by the
% generic templates. Very few real spikes are missed in this way. 
st3 = standalone_detector(rez, spkTh);

% binning width across Y (um)
dd = 5;

% detected depths
dep = st3(:,2);

% min and max for the range of depths
dmin = ymin - 1;
dep = dep - dmin;

dmax  = 1 + ceil(max(dep)/dd);
Nbatches      = rez.temp.Nbatch;

% which batch each spike is coming from
batch_id = st3(:,5); %ceil(st3(:,1)/dt);

% preallocate matrix of counts with 20 bins, spaced logarithmically
F = zeros(dmax, 20, Nbatches);
for t = 1:Nbatches
    % find spikes in this batch
    ix = find(batch_id==t);
    
    % subtract offset
    dep = st3(ix,2) - dmin;
    
    % amplitude bin relative to the minimum possible value
    amp = log10(min(99, st3(ix,3))) - log10(spkTh);
    
    % normalization by maximum possible value
    amp = amp / (log10(100) - log10(spkTh));
    
    % multiply by 20 to distribute a [0,1] variable into 20 bins
    % sparse is very useful here to do this binning quickly
    M = sparse(ceil(dep/dd), ceil(1e-5 + amp * 20), ones(numel(ix), 1), dmax, 20);    
    
    % the counts themselves are taken on a logarithmic scale (some neurons
    % fire too much!)
    F(:, :, t) = log2(1+M);
end

%%
% the 'midpoint' branch is for chronic recordings that have been
% concatenated in the binary file
if isfield(ops, 'midpoint')
    % register the first block as usual
    [imin1, F1] = align_block(F(:, :, 1:ops.midpoint));
    % register the second block as usual
    [imin2, F2] = align_block(F(:, :, ops.midpoint+1:end));
    % now register the average first block to the average second block
    d0 = align_pairs(F1, F2);
    % concatenate the shifts
    imin = [imin1 imin2 + d0];
    imin = imin - mean(imin);
    ops.datashift = 1;
else
    % determine registration offsets 
    ysamp = dmin + dd * [1:dmax] - dd/2;
    [imin,yblk, F0] = align_block2(F, ysamp, ops.nblocks);
end

%%
if getOr(ops, 'fig', 1)  
    figure(193)
    % plot the shift trace in um
    plot(imin * dd)
    drawnow
    
    figure;
    % raster plot of all spikes at their original depths
    st_shift = st3(:,2); %+ imin(batch_id)' * dd;
    for j = spkTh:100
        % for each amplitude bin, plot all the spikes of that size in the
        % same shade of gray
        ix = st3(:, 3)==j; % the amplitudes are rounded to integers
        plot(st3(ix, 1), st_shift(ix), '.', 'color', [1 1 1] * max(0, 1-j/40)) % the marker color here has been carefully tuned
        hold on
    end
    axis tight
end

% if we're creating a registered binary file for visualization in Phy
if ~isempty(getOr(ops, 'fbinaryproc', []))
    fid2 = fopen(ops.fbinaryproc, 'w');
    fclose(fid2);
end

% convert to um 
dshift = imin * dd;
% sort in case we still want to do "tracking"

[~, rez.iorig] = sort(mean(dshift, 2));

% sigma for the Gaussian process smoothing
sig = rez.ops.sig;
% register the data batch by batch
for ibatch = 1:Nbatches
    shift_batch_on_disk2(rez, ibatch, dshift(ibatch, :), yblk, sig);
end
fprintf('time %2.2f, Shifted up/down %d batches. \n', toc, Nbatches)

% keep track of dshift 
rez.dshift = dshift;
% keep track of original spikes
rez.st0 = st3;


% next, we can just run a normal spike sorter, like Kilosort1, and forget about the transformation that has happened in here 

%%



