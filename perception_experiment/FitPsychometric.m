function fit = FitPsychometric(data, opts)
% FitPsychometric  Maximum-likelihood psychometric function for a RunPerceptionExperiment data file.
%
%   fit = FitPsychometric("data/P01_20260917_141500.tsv")
%   fit = FitPsychometric(["data/P01_a.tsv" "data/P01_b.tsv"])        % sessions pooled
%   fit = FitPsychometric(file, 'Function', "normal", 'Lapse', "none", 'By', "none")
%   fit = FitPsychometric(T)                                          % a trial table
%
% Reads the trials (columns a and resp_s: 1 = the participant said /s/;
% rows whose phase column is not "main", i.e. the practice block, are
% dropped; files without a phase column are used whole) and fits, separately for every level of the By columns (default: per vowel),
%
%   P("s" | a) = gamma + (1 - gamma - lambda) * F((a - mu) / sigma)
%
% where F is the logistic 1/(1 + exp(-z)) (default) or the cumulative normal,
% mu its midpoint and sigma its scale, both in units of a. gamma and lambda
% are the lapse rates at the /sh/ and the /s/ end (the proportion of "s"
% answers to a clear /sh/, and of "sh" answers to a clear /s/). With
% 'Lapse', "symmetric" (default) one rate is fitted, gamma = lambda, in
% [0, LapseMax]; "free" fits the two separately; "none" fixes both at 0,
% which biases sigma upward when the participant does lapse (Wichmann & Hill
% 2001, Percept Psychophys 63:1293).
%
% ESTIMATION is by maximum likelihood: the binomial log-likelihood
% sum_i [k_i log p_i + (n_i - k_i) log(1 - p_i)] over the levels (k_i "s"
% answers in n_i trials; identical to the Bernoulli likelihood of the single
% trials) is maximised with fminsearch (no toolbox needed) over mu,
% log(sigma - 0.001) and the logit of lapse/LapseMax, from the two best
% points of a coarse grid. sigma is bounded below at 0.001 because with
% perfectly separated data (all "sh" below some level, all "s" above it) the
% likelihood keeps rising as sigma -> 0.
%
% CONFIDENCE INTERVALS are 95 % percentile intervals from a parametric
% bootstrap (NBoot data sets drawn from the fitted function at the tested
% levels and trial counts, each refitted). The same replicates give a
% goodness-of-fit p value: the proportion whose deviance is at least the
% observed one (small p = the data are further from the curve than binomial
% noise explains).
%
% Options (name, value):
%   By        columns that define separate fits (default "vowel"; e.g.
%             ["vowel" "talker"]; "none" = one fit to all trials)
%   Function  "logistic" (default) or "normal"
%   Lapse     "symmetric" (default), "free" or "none"
%   LapseMax  upper bound of a lapse rate (default 0.1)
%   NBoot     bootstrap replicates (default 1000; 0 = no intervals)
%   Seed      seed of the bootstrap (default 1)
%   Plot      draw the figure (default true): per fit the proportion of "s"
%             answers at each level with its 95 % Wilson interval, the fitted
%             curve, a dotted line at the boundary and, under the 0.5 line,
%             a bar for the boundary's bootstrap interval
%   Save      write <data file>_fit.tsv and, if Plot, <data file>_fit.png
%             next to the (first) data file (default true; ignored for a
%             table input)
%
% Output: struct array, one element per fit, with fields
%   group      the By values, e.g. struct('vowel', "i");  label  for display
%   nTrials, levels (table: a, n, k, p, and the fitted pFit)
%   mu, sigma, gamma, lambda   the MLE
%   pse        the category boundary: a at which P("s") = 0.5 (= mu unless
%              the lapse rates differ)
%   slope      dP/da at the pse (per unit a)
%   width      a(F = 0.75) - a(F = 0.25), the interquartile width of F
%   nll, deviance, pDeviance
%   ci         struct of [lo hi] for pse, mu, sigma, slope, width, gamma, lambda
%   boot       table of the bootstrap replicates
%   predict    function handle, P("s") at any a
%
% See also RunPerceptionExperiment.

arguments
    data
    opts.By (1,:) string = "vowel"
    opts.Function (1,1) string {mustBeMember(opts.Function, ["logistic" "normal"])} = "logistic"
    opts.Lapse (1,1) string {mustBeMember(opts.Lapse, ["symmetric" "free" "none"])} = "symmetric"
    opts.LapseMax (1,1) double {mustBeInRange(opts.LapseMax, 0, 0.5, "exclude-lower")} = 0.1
    opts.NBoot (1,1) double {mustBeInteger, mustBeNonnegative} = 1000
    opts.Seed (1,1) double = 1
    opts.Plot (1,1) logical = true
    opts.Save (1,1) logical = true
end

% ------------------------------------------------------------------- data
if istable(data)
    T = data;
    outBase = "";
else
    files = string(data);
    parts = cell(numel(files), 1);
    for i = 1:numel(files)
        if ~isfile(files(i)), error("FitPsychometric:noFile", "Data file not found: %s", files(i)); end
        parts{i} = readtable(files(i), 'FileType', 'text', 'Delimiter', '\t', 'TextType', 'string');
    end
    T = vertcat(parts{:});
    [d, n] = fileparts(files(1));
    outBase = fullfile(d, n + "_fit");
end
need = ["a" "resp_s"];
if any(opts.By == "none" | opts.By == ""), opts.By = strings(1, 0); end
missing = setdiff([need opts.By], string(T.Properties.VariableNames));
if ~isempty(missing)
    error("FitPsychometric:columns", "Column(s) missing from the data: %s", strjoin(missing, ", "));
end
if ismember("phase", string(T.Properties.VariableNames)), T = T(string(T.phase) == "main", :); end
T = T(~isnan(T.resp_s) & ~isnan(T.a), :);
if isempty(T), error("FitPsychometric:noTrials", "No main-phase trials in the data."); end

if isempty(opts.By)
    G = ones(height(T), 1);  groups = table();
else
    [G, groups] = findgroups(T(:, opts.By));
end
nG = max(G);

% ------------------------------------------------------------------- fits
M = struct('fun', opts.Function, 'lapse', opts.Lapse, 'lapseMax', opts.LapseMax, 'sigmaMin', 1e-3);
rs = RandStream('mt19937ar', 'Seed', opts.Seed);
fits = cell(nG, 1);
for g = 1:nG
    Tg = T(G == g, :);
    [ga, lev] = findgroups(round(Tg.a, 6));
    L = table(lev, splitapply(@numel, Tg.resp_s, ga), splitapply(@sum, Tg.resp_s, ga), 'VariableNames', ["a" "n" "k"]);
    L.p = L.k ./ L.n;

    f = struct();
    if isempty(opts.By), f.group = struct();  else, f.group = table2struct(groups(g, :)); end
    f.label = groupLabel(f.group);
    f.nTrials = height(Tg);
    if height(L) < 3
        warning("FitPsychometric:fewLevels", "%s: only %d levels; mu and sigma are not both identifiable.", f.label, height(L));
    end

    [theta, nll] = fitMle(L.a, L.n, L.k, M, []);
    f = fillParams(f, theta, M);
    L.pFit = psi(theta, L.a, M);
    f.levels = L;
    f.nll = nll;
    f.deviance = deviance(L.n, L.k, L.pFit);
    f.predict = @(a) psi(theta, a, M);

    % parametric bootstrap
    names = ["pse" "mu" "sigma" "slope" "width" "gamma" "lambda"];
    B = nan(opts.NBoot, numel(names) + 1);
    for b = 1:opts.NBoot
        kb = arrayfun(@(n, p) sum(rand(rs, 1, n) < p), L.n, L.pFit);
        [tb, ~] = fitMle(L.a, L.n, kb, M, theta);
        fb = fillParams(struct(), tb, M);
        B(b, :) = [cellfun(@(nm) fb.(nm), cellstr(names)), deviance(L.n, kb, psi(tb, L.a, M))];
    end
    f.boot = array2table(B, 'VariableNames', [names "deviance"]);
    f.ci = struct();
    for nm = names
        if opts.NBoot > 0, f.ci.(nm) = prctileLocal(f.boot.(nm), [2.5 97.5]); else, f.ci.(nm) = [NaN NaN]; end
    end
    if opts.NBoot > 0, f.pDeviance = mean(f.boot.deviance >= f.deviance - 1e-9); else, f.pDeviance = NaN; end

    if f.pse < min(L.a) || f.pse > max(L.a)
        warning("FitPsychometric:pseOutside", "%s: the boundary (%.3f) lies outside the tested levels; it is an extrapolation.", f.label, f.pse);
    end
    if f.sigma < 2 * M.sigmaMin
        warning("FitPsychometric:step", "%s: sigma is at its lower bound (step-like data); the slope is not identifiable, use more or finer levels near the boundary.", f.label);
    end
    fits{g} = f;
end
fit = [fits{:}]';

% ---------------------------------------------------------------- report
S = summaryTable(fit, opts);
disp(S(:, ["label" "n_trials" "pse" "pse_lo" "pse_hi" "sigma" "slope" "lapse_sh" "lapse_s" "deviance" "p_deviance"]));
if opts.Save && outBase ~= ""
    writetable(S, outBase + ".tsv", 'FileType', 'text', 'Delimiter', '\t');
    fprintf("wrote %s\n", outBase + ".tsv");
end
if opts.Plot
    h = plotFits(fit, T, opts);
    if opts.Save && outBase ~= ""
        exportgraphics(h, outBase + ".png", 'Resolution', 200);
        fprintf("wrote %s\n", outBase + ".png");
    end
end
end

% =========================================================================
function [theta, nll] = fitMle(a, n, k, M, theta0)
% Nelder-Mead on the negative log-likelihood. theta0 = [] : start from the two
% best points of a grid; otherwise (bootstrap) from theta0 and from theta0 with
% the lapse moved to mid-range, so a replicate can leave a lapse of ~0.
nLapse = find(M.lapse == ["none" "symmetric" "free"]) - 1;
if isempty(theta0)
    span = max(max(a) - min(a), 0.05);
    mus = linspace(min(a), max(a), 25);
    sigs = logspace(log10(0.005), log10(span), 15);
    laps = [-3 0];                                       % logit of lapse/lapseMax: 0.05 and 0.5 of the bound
    if nLapse == 0, laps = 0; end
    [mm, ss, ll] = ndgrid(mus, log(sigs - M.sigmaMin), laps);
    starts = [mm(:), ss(:), repmat(ll(:), 1, nLapse)];
    val = arrayfun(@(i) negLogLik(starts(i, :), a, n, k, M), 1:size(starts, 1));
    [~, o] = sort(val);
    starts = starts(o(1:2), :);
else
    starts = theta0;
    if nLapse > 0, starts = [theta0; theta0(1:2), zeros(1, nLapse)]; end
end
o = optimset('Display', 'off', 'TolX', 1e-5, 'TolFun', 1e-8, 'MaxFunEvals', 3000, 'MaxIter', 3000);
nll = Inf;
for i = 1:size(starts, 1)
    [th, v] = fminsearch(@(th) negLogLik(th, a, n, k, M), starts(i, :), o);
    if v < nll, nll = v;  theta = th; end
end
end

function v = negLogLik(theta, a, n, k, M)
p = min(max(psi(theta, a, M), 1e-9), 1 - 1e-9);
v = -sum(k .* log(p) + (n - k) .* log(1 - p));
end

function [mu, sigma, gamma, lambda] = unpack(theta, M)
mu = theta(1);
sigma = M.sigmaMin + exp(theta(2));
switch M.lapse
    case "none",      gamma = 0;  lambda = 0;
    case "symmetric", gamma = M.lapseMax / (1 + exp(-theta(3)));  lambda = gamma;
    case "free",      gamma = M.lapseMax / (1 + exp(-theta(3)));  lambda = M.lapseMax / (1 + exp(-theta(4)));
end
end

function p = psi(theta, a, M)
[mu, sigma, gamma, lambda] = unpack(theta, M);
z = (a - mu) / sigma;
if M.fun == "logistic", F = 1 ./ (1 + exp(-z)); else, F = 0.5 * erfc(-z / sqrt(2)); end
p = gamma + (1 - gamma - lambda) * F;
end

function f = fillParams(f, theta, M)
[f.mu, f.sigma, f.gamma, f.lambda] = unpack(theta, M);
q = (0.5 - f.gamma) / (1 - f.gamma - f.lambda);         % F at the 50 % point of psi
if M.fun == "logistic"
    z = log(q / (1 - q));  dens = q * (1 - q);  f.width = 2 * log(3) * f.sigma;
else
    z = -sqrt(2) * erfcinv(2 * q);  dens = exp(-z^2 / 2) / sqrt(2 * pi);  f.width = 2 * 0.674489750196082 * f.sigma;
end
f.pse = f.mu + f.sigma * z;
f.slope = (1 - f.gamma - f.lambda) * dens / f.sigma;
end

function D = deviance(n, k, p)
p = min(max(p, 1e-9), 1 - 1e-9);
t1 = k .* log(k ./ (n .* p));            t1(k == 0) = 0;
t2 = (n - k) .* log((n - k) ./ (n .* (1 - p)));  t2(k == n) = 0;
D = 2 * sum(t1 + t2);
end

function q = prctileLocal(x, pct)
% percentiles by linear interpolation of the order statistics (no toolbox)
x = sort(x(~isnan(x)));
m = numel(x);
q = interp1(((1:m) - 0.5) / m * 100, x, pct, 'linear', NaN);
q(pct < 50 & isnan(q)) = x(1);
q(pct > 50 & isnan(q)) = x(end);
end

function s = groupLabel(group)
fn = string(fieldnames(group))';
if isempty(fn), s = "all trials"; return, end
bits = strings(1, numel(fn));
for i = 1:numel(fn)
    v = string(group.(fn(i)));
    if fn(i) == "vowel" && v == "i",     bits(i) = "/i/ she-see";
    elseif fn(i) == "vowel" && v == "u", bits(i) = "/u/ shoe-sue";
    else,                                bits(i) = fn(i) + " " + v;
    end
end
s = strjoin(bits, ", ");
end

function S = summaryTable(fit, opts)
rows = cell(numel(fit), 1);
for g = 1:numel(fit)
    f = fit(g);
    r = struct2table(f.group, 'AsArray', true);
    r.label = f.label;
    r.n_trials = f.nTrials;
    r.n_levels = height(f.levels);
    r.func = opts.Function;
    r.lapse_model = opts.Lapse;
    for nm = ["pse" "mu" "sigma" "slope" "width"]
        r.(nm) = f.(nm);
        r.(nm + "_lo") = f.ci.(nm)(1);
        r.(nm + "_hi") = f.ci.(nm)(2);
    end
    r.lapse_sh = f.gamma;
    r.lapse_s = f.lambda;
    r.nll = f.nll;
    r.deviance = f.deviance;
    r.p_deviance = f.pDeviance;
    r.n_boot = opts.NBoot;
    rows{g} = r;
end
S = vertcat(rows{:});
end

function h = plotFits(fit, T, opts)
% one axes; series colour follows the entity (vowel i = blue, u = orange), not the order
pal = [42 120 214; 235 104 52; 27 175 122; 237 161 0; 232 123 164; 0 131 0; 74 58 167; 227 73 72] / 255;
ink = [0.10 0.10 0.10];  muted = [0.45 0.45 0.43];
h = figure('Color', 'w', 'Position', [100 100 760 520], 'Visible', matlab.lang.OnOffSwitchState(~batchStartupOptionUsed));
ax = axes(h, 'Box', 'off', 'TickDir', 'out', 'FontSize', 12, 'XColor', muted, 'YColor', muted, ...
          'GridColor', muted, 'GridAlpha', 0.15, 'YGrid', 'on', 'XGrid', 'off', 'Layer', 'bottom');
hold(ax, 'on');
allA = arrayfun(@(f) f.levels.a, fit, 'UniformOutput', false);
allA = vertcat(allA{:});
xl = [min(0, min(allA)), max(1, max(allA))];
aa = linspace(xl(1), xl(2), 400)';
plot(ax, xl, [0.5 0.5], '-', 'Color', [muted 0.35], 'LineWidth', 0.75, 'HandleVisibility', 'off');
hl = gobjects(numel(fit), 1);
for g = 1:numel(fit)
    f = fit(g);
    c = pal(min(colourSlot(f, g), size(pal, 1)), :);
    L = f.levels;
    [lo, hi] = wilson(L.k, L.n);
    xd = L.a + (g - (numel(fit) + 1) / 2) * 0.012 * diff(xl);   % points of several fits side by side, not on top of each other
    for i = 1:height(L)                                  % 95 % binomial (Wilson) interval of each point
        plot(ax, xd([i i]), [lo(i) hi(i)], '-', 'Color', [c 0.45], 'LineWidth', 1, 'HandleVisibility', 'off');
    end
    hl(g) = plot(ax, aa, f.predict(aa), '-', 'Color', c, 'LineWidth', 2);
    plot(ax, xd, L.p, 'o', 'MarkerSize', 8, 'MarkerFaceColor', c, 'MarkerEdgeColor', 'w', 'LineWidth', 1.5, 'HandleVisibility', 'off');
    plot(ax, f.pse([1 1]), [0 0.5], ':', 'Color', c, 'LineWidth', 1.25, 'HandleVisibility', 'off');
    if opts.NBoot > 0                                    % bootstrap interval of the boundary, just under the 0.5 line
        y = 0.5 - 0.03 * g;
        plot(ax, f.ci.pse, [y y], '-', 'Color', c, 'LineWidth', 3, 'HandleVisibility', 'off');
        hl(g).DisplayName = sprintf("%s: boundary %.3f [%.3f, %.3f]", f.label, f.pse, f.ci.pse);
    else
        hl(g).DisplayName = sprintf("%s: boundary %.3f", f.label, f.pse);
    end
end
xlim(ax, xl + [-0.03 0.03]);  ylim(ax, [-0.03 1.03]);
xlabel(ax, "continuum position a  (0 = /sh/, 1 = /s/)", 'Color', ink);
ylabel(ax, "proportion of ""s"" responses", 'Color', ink);
who = "";
if ismember("participant", string(T.Properties.VariableNames)), who = strjoin(unique(string(T.participant)), ", ") + ": "; end
title(ax, sprintf("%s%d trials, %s fit, lapse %s", who, height(T), opts.Function, opts.Lapse), 'FontWeight', 'normal', 'Color', ink);
legend(ax, hl, 'Location', 'southeast', 'Box', 'off', 'FontSize', 11, 'TextColor', ink);
end

function s = colourSlot(f, g)
s = g;
if isfield(f.group, 'vowel') && isscalar(fieldnames(f.group))
    s = 1 + (string(f.group.vowel) == "u");
end
end

function [lo, hi] = wilson(k, n)
z = 1.959964;
p = k ./ n;
den = 1 + z^2 ./ n;
mid = (p + z^2 ./ (2 * n)) ./ den;
half = z * sqrt(p .* (1 - p) ./ n + z^2 ./ (4 * n.^2)) ./ den;
lo = mid - half;  hi = mid + half;
end
