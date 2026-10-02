function L = fitSpectrumLda(X, isS, lambda)
% fitSpectrumLda  Shrinkage Fisher discriminant: /sh/ (0) vs /s/ (1) on whole spectra.
%
%   L = fitSpectrumLda(X, isS)            X nTrials x nGrid, isS logical
%   ahat = applySpectrumLda(L, Xnew)      whole-spectrum continuum position
%
% The direction w = (Sw + lambda*mean(diag(Sw))*I)^-1 (mu_s - mu_sh), where
% Sw is the pooled within-class covariance. Scores are affinely rescaled so
% that the /sh/ class mean maps to 0 and the /s/ class mean to 1: "ahat".
if nargin < 3, lambda = 0.1; end
mu0 = mean(X(~isS, :), 1); mu1 = mean(X(isS, :), 1);
Xc = [X(~isS, :) - mu0; X(isS, :) - mu1];
Sw = (Xc.' * Xc) / (size(Xc, 1) - 2);
Sw = Sw + lambda * mean(diag(Sw)) * eye(size(Sw));
w = Sw \ (mu1 - mu0).';
L.w = w; L.b0 = mu0 * w; L.scale = (mu1 - mu0) * w;
L.ahatReal = applySpectrumLda(L, X);
L.accuracy = mean((L.ahatReal > 0.5) == isS(:));
L.mu0 = mu0; L.mu1 = mu1;
end
