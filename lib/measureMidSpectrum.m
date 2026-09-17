function [dB, fHz] = measureMidSpectrum(sib, Fs)
% measureMidSpectrum  Mid-sibilant multitaper spectrum, as the experiment measures it.
%
%   [dB, fHz] = measureMidSpectrum(sib, Fs)
%
% Three 50 ms windows centred at the midpoint -5 / 0 / +5 ms, 7 Slepian
% tapers (pmtm, nw = 4), averaged in linear power, returned in dB on pmtm's
% grid (nfft 4096). This mirrors extract_spectra_one's "m" point, so
% synthetic tokens can be compared with the *_spectra.tsv rows.
W = round(0.050 * Fs); n = numel(sib); acc = 0;
for off = (-5:5:5) / 1000 * Fs
    c = round(n / 2 + off);
    head = max(1, c - round(W/2)); tail = min(n, head + W - 1); head = max(1, tail - W + 1);
    [p, fHz] = pmtm(sib(head:tail), 4, 4096, Fs);
    acc = acc + p;
end
dB = 10 * log10(acc / 3).';
fHz = fHz.';
end
