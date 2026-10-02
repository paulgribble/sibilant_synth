function X = spectrumFeatures(fHz, dB)
% spectrumFeatures  Level-normalised whole-spectrum feature vectors.
%
%   X = spectrumFeatures(fHz, dB)   dB is nTrials x numel(fHz) (any grid)
%
% Resamples each row onto spectrumFeatureGrid (linear interpolation in log
% frequency after a light 3-bin smoothing) and subtracts the row mean, so X
% (nTrials x nGrid) describes spectral SHAPE, independent of recording gain.
gridHz = spectrumFeatureGrid();
fHz = fHz(:).';
keep = fHz > 0;                                  % pmtm grids start at DC
fHz = fHz(keep); dB = dB(:, keep);
dB = movmean(dB, 3, 2);
X = interp1(log2(fHz), dB.', log2(gridHz(:)), 'linear', 'extrap');   % nGrid x nTrials
X = X.';                                                             % nTrials x nGrid (also for one row)
X = X - mean(X, 2);
end
