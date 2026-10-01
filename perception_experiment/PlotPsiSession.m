function h = PlotPsiSession(data, opts)
% PlotPsiSession  Diagnostic plots of a RunPsiExperiment session: where the trials went and how the posterior tightened.
%
%   PlotPsiSession("data/P01_20261001_150000.tsv")
%   h = PlotPsiSession(T, 'Save', false)                 % a trial table
%
% Four panels, one line per talker x vowel function (practice trials are
% dropped; the x axis is the trial count within the function):
%   top left      the level a of every trial (filled = "s", open = "sh")
%                 with the running boundary estimate mu_hat and a band of
%                 +/- 1 posterior SD
%   top right     the running estimate of Measure with a +/- 1 SD band
%   bottom left   the posterior SD of the boundary against trials
%   bottom right  the posterior SD of Measure against trials
% Measure is "width" (default; a(F = 0.75) - a(F = 0.25), 2 ln 3 sigma for
% the logistic), "sigma" or "slope" (dP/da at the boundary,
% (1 - 2 lapse_hat) / (4 sigma) for the logistic). Its SD is the delta-method
% value, estimate x SD of log sigma, so the right-hand panels differ only
% by scale. The SD panels have a log y axis; if the .json next to the file
% records a StopSd, its thresholds are drawn as dotted lines (the second
% converted with the final estimate of Measure). The columns used are a,
% resp_s, mu_hat, sigma_hat, mu_sd, logsigma_sd and lapse_hat, written by
% RunPsiExperiment after every trial; FitPsychometric's bootstrap intervals
% are a separate check.
%
% Options:
%   Measure  "width" (default), "sigma" or "slope"
%   Save     write <data file>_psi.png (width) or <data file>_psi_<Measure>.png
%            next to the data file (default true; ignored for a table input)
%
% Returns the figure handle.
%
% See also RunPsiExperiment, FitPsychometric.

arguments
    data
    opts.Measure (1,1) string {mustBeMember(opts.Measure, ["width" "sigma" "slope"])} = "width"
    opts.Save (1,1) logical = true
end

% ------------------------------------------------------------------- data
stopSd = [];  func = "logistic";  outBase = "";  who = "";
if istable(data)
    T = data;
else
    file = string(data);
    if ~isfile(file), error("PlotPsiSession:noFile", "Data file not found: %s", file); end
    T = readtable(file, 'FileType', 'text', 'Delimiter', '\t', 'TextType', 'string');
    [d, n] = fileparts(file);
    outBase = fullfile(d, n + "_psi");
    if opts.Measure ~= "width", outBase = outBase + "_" + opts.Measure; end
    jsonFile = fullfile(d, n + ".json");
    if isfile(jsonFile)
        info = jsondecode(fileread(jsonFile));
        if isfield(info, 'stopSd'), stopSd = info.stopSd; end
        if isfield(info, 'func'), func = string(info.func); end
    end
end
need = ["a" "resp_s" "mu_hat" "sigma_hat" "mu_sd" "logsigma_sd" "talker" "vowel"];
missing = setdiff(need, string(T.Properties.VariableNames));
if ~isempty(missing)
    error("PlotPsiSession:columns", "Not a RunPsiExperiment file: missing %s.", strjoin(missing, ", "));
end
if ismember("phase", string(T.Properties.VariableNames)), T = T(T.phase == "main", :); end
if ismember("participant", string(T.Properties.VariableNames)), who = strjoin(unique(string(T.participant)), ", ") + ": "; end
if isempty(T), error("PlotPsiSession:noTrials", "No main trials."); end
if ~ismember("lapse_hat", string(T.Properties.VariableNames)), T.lapse_hat = zeros(height(T), 1); end
if func == "logistic", wFac = 2 * log(3);  dens = 0.25;
else,                  wFac = 2 * 0.674489750196082;  dens = 1 / sqrt(2 * pi);
end
switch opts.Measure                                      % the measure and its unit
    case "width", measure = @(S) wFac * S.sigma_hat;                            unit = "units of a";
    case "sigma", measure = @(S) S.sigma_hat;                                   unit = "units of a";
    case "slope", measure = @(S) (1 - 2 * S.lapse_hat) * dens ./ S.sigma_hat;  unit = "per unit a";
end
[G, groups] = findgroups(T(:, ["talker" "vowel"]));
nG = max(G);

% ------------------------------------------------------------------- figure
pal = [42 120 214; 235 104 52; 27 175 122; 237 161 0; 232 123 164; 0 131 0; 74 58 167; 227 73 72] / 255;
ink = [0.10 0.10 0.10];  muted = [0.45 0.45 0.43];
h = figure('Color', 'w', 'Position', [100 100 1100 760], 'Visible', matlab.lang.OnOffSwitchState(~batchStartupOptionUsed));
tl = tiledlayout(h, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tl, sprintf("%s%d trials, Psi method", who, height(T)), 'FontWeight', 'normal', 'Color', ink);
ax = gobjects(1, 4);
for k = 1:4
    ax(k) = nexttile(tl);
    set(ax(k), 'Box', 'off', 'TickDir', 'out', 'FontSize', 11, 'XColor', muted, 'YColor', muted, ...
               'GridColor', muted, 'GridAlpha', 0.15, 'YGrid', 'on', 'Layer', 'bottom');
    hold(ax(k), 'on');
end
set(ax(3:4), 'YScale', 'log');
hl = gobjects(nG, 1);
wLast = zeros(nG, 1);
if isscalar(unique(groups.talker)), slot = 1 + (groups.vowel == "u"); else, slot = (1:nG)'; end   % vowel i blue, u orange
for g = 1:nG
    S = T(G == g, :);
    n = (1:height(S))';
    c = pal(min(slot(g), size(pal, 1)), :);
    w = measure(S);
    wSd = w .* S.logsigma_sd;                            % delta method
    wLast(g) = w(end);
    lab = groups.talker(g) + " " + groups.vowel(g);

    band(ax(1), n, S.mu_hat - S.mu_sd, S.mu_hat + S.mu_sd, c);
    hl(g) = plot(ax(1), n, S.mu_hat, '-', 'Color', c, 'LineWidth', 1.75, 'DisplayName', lab);
    isS = S.resp_s == 1;
    plot(ax(1), n(isS), S.a(isS), 'o', 'MarkerSize', 4.5, 'MarkerFaceColor', c, 'MarkerEdgeColor', c, 'HandleVisibility', 'off');
    plot(ax(1), n(~isS), S.a(~isS), 'o', 'MarkerSize', 4.5, 'MarkerFaceColor', 'w', 'MarkerEdgeColor', c, 'HandleVisibility', 'off');

    band(ax(2), n, max(w - wSd, 0), w + wSd, c);
    plot(ax(2), n, w, '-', 'Color', c, 'LineWidth', 1.75);

    plot(ax(3), n, S.mu_sd, '-', 'Color', c, 'LineWidth', 1.75);
    plot(ax(4), n, wSd, '-', 'Color', c, 'LineWidth', 1.75);
end
nMax = max(splitapply(@numel, T.a, G));
set(ax, 'XLim', [1 nMax]);
if numel(stopSd) == 2
    xl = [1 nMax];
    plot(ax(3), xl, stopSd([1 1]), ':', 'Color', ink, 'LineWidth', 1);
    for g = 1:nG
        plot(ax(4), xl, wLast(g) * stopSd([2 2]), ':', 'Color', ink, 'LineWidth', 1);
    end
end
for k = 3:4, yl = ylim(ax(k));  ylim(ax(k), yl .* [0.8 1.25]); end   % keep the threshold lines off the axis edge
ylim(ax(1), [-0.02 1.02]);
titles = ["trial levels (filled = ""s"", open = ""sh"") and boundary estimate +/- 1 SD", opts.Measure + " estimate +/- 1 SD", ...
          "posterior SD of the boundary", "posterior SD of the " + opts.Measure];
ylabels = ["a  (0 = /sh/, 1 = /s/)", opts.Measure + "  (" + unit + ")", "SD  (units of a)", "SD  (" + unit + ")"];
for k = 1:4
    title(ax(k), titles(k), 'FontWeight', 'normal', 'FontSize', 11, 'Color', ink);
    ylabel(ax(k), ylabels(k), 'Color', ink);
    xlabel(ax(k), "trial (within the function)", 'Color', ink);
end
if nG > 1, legend(ax(1), hl, 'Location', 'northeast', 'Box', 'off', 'FontSize', 10, 'TextColor', ink); end

if opts.Save && outBase ~= ""
    exportgraphics(h, outBase + ".png", 'Resolution', 200);
    fprintf("wrote %s\n", outBase + ".png");
end
end

% -------------------------------------------------------------------------
function band(ax, x, lo, hi, c)
fill(ax, [x; flipud(x)], [lo; flipud(hi)], c, 'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');
end
