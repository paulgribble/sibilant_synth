function ahat = applySpectrumLda(L, X)
% applySpectrumLda  Whole-spectrum continuum position (0 = /sh/ mean, 1 = /s/ mean).
ahat = (X * L.w - L.b0) / L.scale;
end
