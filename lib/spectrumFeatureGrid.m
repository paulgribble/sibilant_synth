function [gridHz, band] = spectrumFeatureGrid()
% spectrumFeatureGrid  The grid on which whole-spectrum comparisons are made.
%
%   [gridHz, band] = spectrumFeatureGrid()
%
% 1/12-octave centres from 500 Hz to 16 kHz (61 bins), band = [500 16000].
% Level (mic gain) is uncalibrated per participant, so features are the dB
% spectrum on this grid minus its mean over the grid (see spectrumFeatures).
band = [500 16000];
gridHz = 2 .^ (log2(band(1)):(1/12):log2(band(2)));
end
