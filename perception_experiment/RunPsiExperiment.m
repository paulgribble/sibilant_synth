function [T, dataFile, est] = RunPsiExperiment(participant, opts)
% RunPsiExperiment  Adaptive two-alternative identification on the /sh/ -- /s/ continuum (Psi method).
%
%   RunPsiExperiment("P01")                                      % she/see, 100 trials, levels 0:0.01:1
%   RunPsiExperiment("P01", 'MaxTrials', 150, 'StopSd', [0.015 0.25])   % stop earlier once that precise
%   RunPsiExperiment("P01", 'Vowels', ["i" "u"])                 % two functions, trials intermixed
%   [T, dataFile, est] = RunPsiExperiment("sim", 'Simulate', [0.55 0.03 0.02])
%
% The same task, window, keys, practice block and data format as
% RunPerceptionExperiment, but the level a of each trial is chosen while
% the session runs, by the Psi method of Kontsevich & Tyler (1999): a
% Bayesian posterior over the boundary mu, the scale sigma and a lapse rate
% is kept for every talker x vowel (PsiMethod), and each trial is placed at
% the level expected to reduce the uncertainty about mu and log sigma most,
% lapse marginalised out (Prins 2013). Trials therefore cluster at the
% current boundary estimate and about one sigma either side of it, where
% the slope is measured, instead of being spread over a fixed grid, so
% fewer trials give the same precision and no grid has to be chosen in
% advance. Each function opens with the Opening levels in random order
% (default 0.3:0.05:0.7, 9 trials), so every listener first hears a set
% that brackets the middle of the continuum whatever they answer; their
% responses enter the posterior like any other, and the Psi rule chooses
% from then on. With several talkers or vowels each round of trials visits
% every function in random order.
%
% STOPPING. Each function ends after MaxTrials trials, or earlier once
% (from MinTrials on) the posterior SD of mu is at most StopSd(1) and that
% of log sigma at most StopSd(2). The posterior SDs match the actual error
% of the estimates to within about 10 % in simulation, so StopSd =
% [0.015 0.25] means: boundary known to about +/- 0.015, sigma to about
% +/- 25 %. Over the pilot range (boundary 0.45 - 0.55, sigma 0.02 - 0.07,
% lapse 0 - 3 %) the per-session boundary RMSE is 0.007 - 0.029 after 50
% trials, 0.005 - 0.021 after 100 and 0.004 - 0.016 after 150 (about 0.3
% sigma at 100), and the SD of log sigma 0.32 - 0.41, 0.22 - 0.26 and
% 0.18 - 0.21, the same whatever the true boundary. The 136-trial
% constant-stimuli design of RunPerceptionExperiment, fitted by maximum
% likelihood, gives 0.008 - 0.019 and 0.26 - 0.80 on the same listeners;
% the Psi method matches it in 75 - 125 trials. With StopSd = [0.015 0.25]
% and MaxTrials 150 a session ends after about 105 trials for sigma <= 0.04
% and 145 - 150 for sigma = 0.07. sigma is underestimated by about 10 %
% when the listener never lapses, because the prior allows lapses; the
% maximum-likelihood fit shows the same bias. Analyse with FitPsychometric
% as usual (its likelihood does not care how the levels were chosen) or use
% the posterior estimates in the .json and the trial rows; PlotPsiSession
% draws the trial levels and the posterior SDs against trials.
%
% Options (name, value), those of RunPerceptionExperiment unless noted:
%   Levels      levels a trial may be placed at, in [0, 1], at most 3 decimals
%               (default 0:0.01:1; all are synthesised up front)
%   Opening     levels of the first trials of every function, played in
%               random order before the Psi rule starts choosing (default
%               0.3:0.05:0.7; [] = none). They count towards MaxTrials.
%   MaxTrials   trials per talker x vowel (default 100)
%   StopSd      [] (default) = run MaxTrials; [sdMu sdLogSigma] = stop a
%               function once both posterior SDs are at most these
%   MinTrials   trials before StopSd is checked (default 30)
%   SigmaRange  [lo hi] of the sigma grid of the posterior (default [0.005 0.5])
%   Lapse       lapse rates on the grid (default [0 0.01 0.02 0.04 0.08])
%   Function    "logistic" (default) or "normal"
%   Practice    endpoint repetitions per talker x vowel in the practice block (default 3)
%   Vowels, Talkers, StimDir, DataDir, Keys, ShSide, ItiS, BreakEvery,
%   Regenerate, WindowState   as in RunPerceptionExperiment
%   Seed        seed of the practice order, the opening order and the order
%               of the functions within a round; the Psi choice itself is
%               deterministic
%   Simulate    [] or [pse sigma lapse], as in RunPerceptionExperiment
%
% Output files, in DataDir:
%   <participant>_<yyyymmdd_HHMMSS>.tsv   one row per trial, the columns of
%       RunPerceptionExperiment (block omitted) plus pick ("opening" or
%       "psi": how the level was chosen; "" in practice) and mu_hat,
%       sigma_hat, mu_sd, logsigma_sd, lapse_hat: the posterior of that
%       trial's function after the response (NaN in practice)
%   <participant>_<yyyymmdd_HHMMSS>.json  the options, the seed, and per
%       talker x vowel the final estimate (n, why it stopped, mu, sigma,
%       their SDs and 95 % credible intervals, lapse, slope, width)
%
% Returns the trial table T, the path of the .tsv and the estimates as a table.
%
% See also PsiMethod, PlotPsiSession, RunPerceptionExperiment, FitPsychometric, PreparePerceptionStimuli.

arguments
    participant (1,1) string
    opts.Levels (1,:) double {mustBeInRange(opts.Levels, 0, 1)} = 0:0.01:1
    opts.Opening (1,:) double {mustBeInRange(opts.Opening, 0, 1)} = 0.3:0.05:0.7
    opts.MaxTrials (1,1) double {mustBeInteger, mustBePositive} = 100
    opts.StopSd (1,:) double {mustBePositive} = []
    opts.MinTrials (1,1) double {mustBeInteger, mustBeNonnegative} = 30
    opts.SigmaRange (1,2) double {mustBePositive} = [0.005 0.5]
    opts.Lapse (1,:) double {mustBeInRange(opts.Lapse, 0, 0.5, "exclude-upper")} = [0 0.01 0.02 0.04 0.08]
    opts.Function (1,1) string {mustBeMember(opts.Function, ["logistic" "normal"])} = "logistic"
    opts.Practice (1,1) double {mustBeInteger, mustBeNonnegative} = 3
    opts.Vowels (1,:) string = "i"
    opts.Talkers (1,:) string = "pert4P17"
    opts.StimDir (1,1) string = ""
    opts.DataDir (1,1) string = ""
    opts.Keys (1,2) string = ["f" "j"]
    opts.ShSide (1,1) string {mustBeMember(opts.ShSide, ["left" "right"])} = "left"
    opts.ItiS (1,1) double {mustBeNonnegative} = 0.75
    opts.BreakEvery (1,1) double {mustBeInteger, mustBeNonnegative} = 0
    opts.Seed = []
    opts.Regenerate (1,1) logical = false
    opts.WindowState (1,1) string {mustBeMember(opts.WindowState, ["maximized" "fullscreen" "normal"])} = "maximized"
    opts.Simulate double = []
end

here = fileparts(mfilename('fullpath'));
addpath(fileparts(here));                                % SynthSibilant & co.
if opts.StimDir == "", opts.StimDir = fullfile(fileparts(here), "stimuli"); end
if opts.DataDir == "", opts.DataDir = fullfile(here, "data"); end

% ------------------------------------------------------------ check options
if isempty(regexp(participant, '^[A-Za-z0-9\-]+$', 'once'))
    error("RunPsiExperiment:badId", "participant may contain only letters, digits and ""-"", got ""%s"".", participant);
end
if any(abs([opts.Levels opts.Opening] - round([opts.Levels opts.Opening], 3)) > 1e-9)
    error("RunPsiExperiment:badLevels", "Levels and Opening may have at most 3 decimals (they name the WAV files).");
end
opening = round(opts.Opening, 3);
levels = unique(round([opts.Levels opening], 3));        % the opening levels are candidates too
if numel(opening) > opts.MaxTrials
    error("RunPsiExperiment:badOpening", "Opening has %d levels but MaxTrials is %d.", numel(opening), opts.MaxTrials);
end
if numel(levels) < 3, error("RunPsiExperiment:badLevels", "At least 3 distinct levels are needed."); end
if ~isempty(opts.StopSd) && numel(opts.StopSd) ~= 2
    error("RunPsiExperiment:badStopSd", "StopSd must be [] or [sdMu sdLogSigma].");
end
vowels = unique(arrayfun(@normVowel, opts.Vowels), 'stable');
talkers = unique(opts.Talkers, 'stable');
opts.Keys = lower(opts.Keys);
if opts.Keys(1) == opts.Keys(2) || any(ismember(opts.Keys, ["escape" "space"]))
    error("RunPsiExperiment:badKeys", "Keys must be two different keys, not escape or space.");
end
simulate = ~isempty(opts.Simulate);
if simulate && numel(opts.Simulate) ~= 3
    error("RunPsiExperiment:badSimulate", "Simulate must be [pse sigma lapse].");
end

% words on the two buttons
if isequal(vowels, "i"),     shLabel = "she";        sLabel = "see";
elseif isequal(vowels, "u"), shLabel = "shoe";       sLabel = "sue";
else,                        shLabel = "she / shoe"; sLabel = "see / sue";
end
if opts.ShSide == "left", sideSound = ["sh" "s"]; sideLabel = [shLabel sLabel];
else,                     sideSound = ["s" "sh"]; sideLabel = [sLabel shLabel];
end

% ------------------------------------------------- stimuli (batch, up front)
stimA = levels;
if opts.Practice > 0, stimA = unique([levels 0 1]); end  % the practice block uses the endpoints
stim = PreparePerceptionStimuli(opts.StimDir, talkers, vowels, stimA, 'Regenerate', opts.Regenerate);
nStim = height(stim);
wav = cell(nStim, 1);
wavFs = zeros(nStim, 1);
if ~simulate
    for iw = 1:nStim
        [y, wavFs(iw)] = audioread(stim.path(iw));
        wav{iw} = y(:, 1);
    end
end

% ----------------------------------------- one psychometric function per talker x vowel
[ct, cv] = ndgrid(1:numel(talkers), 1:numel(vowels));
cond = table(reshape(talkers(ct(:)), [], 1), reshape(vowels(cv(:)), [], 1), 'VariableNames', ["talker" "vowel"]);
nCond = height(cond);
stimOf = zeros(nCond, numel(levels));                    % stim row of each condition x level
for c = 1:nCond
    for l = 1:numel(levels)
        stimOf(c, l) = find(stim.talker == cond.talker(c) & stim.vowel == cond.vowel(c) & abs(stim.a - levels(l)) < 1e-9, 1);
    end
end
psi = cell(nCond, 1);
for c = 1:nCond
    psi{c} = PsiMethod(levels, 'MuRange', [min(levels) max(levels)], 'SigmaRange', opts.SigmaRange, ...
                       'Lapse', opts.Lapse, 'Function', opts.Function);
end
stopped = strings(nCond, 1);                             % "" while running; "maxTrials" / "precision" / "aborted"
nMax = nCond * opts.MaxTrials;

% ------------------------------------------------------------- practice order
seed = opts.Seed;
if isempty(seed), seed = randi(RandStream('mt19937ar', 'Seed', 'shuffle'), 2^31 - 2); end
rs = RandStream('mt19937ar', 'Seed', seed);
iPrac = find(stim.a == 0 | stim.a == 1);
pracOrder = zeros(numel(iPrac), opts.Practice);
for r = 1:opts.Practice, pracOrder(:, r) = iPrac(randperm(rs, numel(iPrac))); end
pracOrder = pracOrder(:);
nPrac = numel(pracOrder);
openOrder = cell(nCond, 1);                              % the opening levels of each function, shuffled
for c = 1:nCond, openOrder{c} = opening(randperm(rs, numel(opening))); end

% ------------------------------------------------------------- output files
if ~isfolder(opts.DataDir), mkdir(opts.DataDir); end
stamp = string(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
dataFile = fullfile(opts.DataDir, participant + "_" + stamp + ".tsv");
infoFile = fullfile(opts.DataDir, participant + "_" + stamp + ".json");
info = struct('participant', participant, 'method', "psi", 'started', string(datetime('now')), 'completed', false, ...
              'nTrialsMax', nMax, 'nTrialsDone', 0, 'nPracticePlanned', nPrac, 'nPracticeDone', 0, ...
              'levels', levels, 'opening', opening, 'maxTrials', opts.MaxTrials, 'minTrials', opts.MinTrials, 'stopSd', opts.StopSd, ...
              'sigmaRange', opts.SigmaRange, 'lapse', opts.Lapse, 'func', opts.Function, 'practiceReps', opts.Practice, ...
              'vowels', vowels, 'talkers', talkers, 'stimDir', opts.StimDir, 'keys', opts.Keys, ...
              'shSide', opts.ShSide, 'itiS', opts.ItiS, 'breakEvery', opts.BreakEvery, ...
              'orderSeed', seed, 'simulate', opts.Simulate, 'estimates', []);
writeInfo();
fid = fopen(dataFile, 'w');                              % 'w' flushes after every write
if fid < 0, error("RunPsiExperiment:noFile", "Cannot write %s.", dataFile); end
closeFile = onCleanup(@() fclose(fid));
fprintf(fid, "participant\tphase\ttrial\ttalker\tvowel\ta\tfilename\tresponse\tresp_s\tword\tinput\trt_s\tsh_side\ttime\tpick\tmu_hat\tsigma_hat\tmu_sd\tlogsigma_sd\tlapse_hat\n");

% ---------------------------------------------------------------- run
St = struct('phase', "idle", 'abort', false, 'side', 0, 'how', "", 'rt', NaN, 't0', uint64(0));
nDone = 0;                                               % main trials answered
nPracDone = 0;
if simulate
    session(@(~, ~) [], @(~) [], @simTrial);
else
    runGui();
end
stopped(stopped == "") = "aborted";

est = estimates();
info.completed = all(stopped ~= "aborted");
info.nTrialsDone = nDone;
info.nPracticeDone = nPracDone;
info.finished = string(datetime('now'));
info.estimates = table2struct(est);
writeInfo();
clear closeFile
T = readtable(dataFile, 'FileType', 'text', 'Delimiter', '\t', 'TextType', 'string');
fprintf("%d trials (at most %d) saved to %s\n", nDone, nMax, dataFile);
if nPracDone > 0
    P = T(T.phase == "practice", :);
    fprintf("  practice: %d of %d endpoint tokens answered as expected (a = 0 ""sh"", a = 1 ""s"")\n", sum(P.resp_s == P.a), height(P));
end
for c = 1:nCond
    fprintf("  %s %s: %d trials (%s), boundary %.3f +/- %.3f, sigma %.3f [%.3f, %.3f], slope %.1f\n", ...
            est.talker(c), est.vowel(c), est.n(c), est.stopped(c), est.mu(c), est.mu_sd(c), est.sigma(c), est.sigma_lo(c), est.sigma_hi(c), est.slope(c));
end

% =========================================================================
    function session(showScreen, setProgress, doTrial)
        % the whole session: practice, then rounds over the running functions.
        % doTrial(k) plays stim k and returns true with St.side / St.how / St.rt set, false on abort
        pracNote = "";  startText = "Start (space bar)";
        if nPrac > 0
            pracNote = sprintf("\n\nFirst, %d practice trials.", nPrac);
            startText = "Start the practice (space bar)";
        end
        showScreen(sprintf("You will hear one word on each trial. Was it ""%s"" or ""%s""?\n\n" + ...
                           """%s"": press %s or click the left button\n""%s"": press %s or click the right button\n\n" + ...
                           "Answer once the word has ended. If you are unsure, go with your first impression." + pracNote, ...
                           sideLabel(1), sideLabel(2), sideLabel(1), upper(opts.Keys(1)), sideLabel(2), upper(opts.Keys(2))), startText);
        if St.abort, return, end
        for i = 1:nPrac
            setProgress(sprintf("practice %d / %d", i, nPrac));
            if ~doTrial(pracOrder(i)), return, end
            writeTrial("practice", i, pracOrder(i), sideSound(St.side) == "s", St.how, St.rt, "", []);
        end
        if nPrac > 0
            atMost = "";  if ~isempty(opts.StopSd), atMost = "at most "; end
            showScreen(sprintf("That was the practice.\n\nThe main part starts now: %s%d trials, same task.\n" + ...
                               "Some words will be less clear than others; just give your best answer.", atMost, nMax), "Start (space bar)");
            if St.abort, return, end
        end
        t = 0;
        while any(stopped == "")                         % one round = every running function once, in random order
            active = find(stopped == "");
            for ci = active(randperm(rs, numel(active)))'
                t = t + 1;
                if opts.BreakEvery > 0 && t > 1 && mod(t - 1, opts.BreakEvery) == 0
                    showScreen(sprintf("Time for a short break.\n%d trials done.", t - 1), "Continue (space bar)");
                    if St.abort, return, end
                end
                setProgress(sprintf("%d / %d", t, nMax));
                nDoneC = size(psi{ci}.history, 1);
                if nDoneC < numel(opening), a = openOrder{ci}(nDoneC + 1);  pick = "opening";
                else,                       a = psi{ci}.next();            pick = "psi";
                end
                k = stimOf(ci, abs(levels - a) < 1e-9);
                if ~doTrial(k), return, end
                saidS = sideSound(St.side) == "s";
                psi{ci}.update(a, saidS);
                e = psi{ci}.estimate();
                writeTrial("main", t, k, saidS, St.how, St.rt, pick, e);
                if e.n >= opts.MaxTrials
                    stopped(ci) = "maxTrials";
                elseif ~isempty(opts.StopSd) && e.n >= opts.MinTrials && e.muSd <= opts.StopSd(1) && e.logSigmaSd <= opts.StopSd(2)
                    stopped(ci) = "precision";
                end
            end
        end
    end

    function ok = simTrial(k)
        p = opts.Simulate(3) + (1 - 2 * opts.Simulate(3)) / (1 + exp(-(stim.a(k) - opts.Simulate(1)) / opts.Simulate(2)));
        snd = ["sh" "s"];
        St.side = find(sideSound == snd((rand(rs) < p) + 1));
        St.how = "sim";  St.rt = NaN;
        ok = true;
    end

    function runGui()
        fig = uifigure('Name', "Listening experiment", 'Color', [1 1 1], 'Position', [100 100 1000 700], 'WindowState', opts.WindowState, ...
                       'WindowKeyPressFcn', @onKey, 'CloseRequestFcn', @(~, ~) closeRequest());
        gl = uigridlayout(fig, [4 2], 'RowHeight', {'3x', '3x', '1x', 30}, 'ColumnWidth', {'1x', '1x'}, ...
                          'Padding', [60 30 60 30], 'ColumnSpacing', 60, 'RowSpacing', 20, 'BackgroundColor', [1 1 1]);
        msg = uilabel(gl, 'Text', "", 'FontSize', 20, 'HorizontalAlignment', 'center', 'WordWrap', 'on');
        msg.Layout.Row = 1;  msg.Layout.Column = [1 2];
        idle = [0.94 0.94 0.94];  chosen = [0.55 0.75 0.95];
        btn = gobjects(1, 2);
        for s = 1:2
            btn(s) = uibutton(gl, 'Text', [sideLabel(s), "(" + upper(opts.Keys(s)) + ")"], 'FontSize', 44 - 14 * (numel(vowels) > 1), 'WordWrap', 'on', ...
                              'BackgroundColor', idle, 'Enable', 'off', 'ButtonPushedFcn', @(~, ~) respond(s, "button"));
            btn(s).Layout.Row = 2;  btn(s).Layout.Column = s;
        end
        go = uibutton(gl, 'Text', "Start (space bar)", 'FontSize', 24, 'ButtonPushedFcn', @(~, ~) start());
        go.Layout.Row = 3;  go.Layout.Column = [1 2];
        prog = uilabel(gl, 'Text', "", 'FontSize', 14, 'FontColor', [0.5 0.5 0.5], 'HorizontalAlignment', 'center');
        prog.Layout.Row = 4;  prog.Layout.Column = [1 2];

        % The window is deleted explicitly: an onCleanup here would never fire, because
        % this workspace is kept alive by the window's own callbacks (nested functions).
        try
            session(@waitStart, @(s) set(prog, 'Text', s), @guiTrial);
            if isvalid(fig) && ~St.abort
                msg.Text = "Finished. Thank you!";
                prog.Text = "";
                pause(2);
            end
        catch err
            if isvalid(fig), delete(fig); end
            rethrow(err);
        end
        if isvalid(fig), delete(fig); end

        % ---- nested: one trial, screens and callbacks
        function ok = guiTrial(k)
            ok = false;
            pause(opts.ItiS);
            if St.abort, return, end
            player = audioplayer(wav{k}, wavFs(k));      % held until the function returns, so it is not deleted mid-playback
            St.phase = "play";
            play(player);
            St.t0 = tic;
            pause(numel(wav{k}) / wavFs(k));             % callbacks run, but responses are ignored until the token ends
            if St.abort, return, end
            St.phase = "respond";
            set(btn, 'Enable', 'on');
            uiwait(fig);
            if St.abort || ~isvalid(fig), return, end
            btn(St.side).BackgroundColor = chosen;
            pause(0.15);
            if St.abort || ~isvalid(fig), return, end
            btn(St.side).BackgroundColor = idle;
            set(btn, 'Enable', 'off');
            ok = true;
        end
        function waitStart(text, buttonText)
            msg.Text = text;  prog.Text = "";
            go.Text = buttonText;  go.Visible = 'on';
            set(btn, 'Enable', 'off');
            St.phase = "start";
            figure(fig);
            uiwait(fig);
            if isvalid(fig), msg.Text = "";  go.Visible = 'off'; end
        end
        function start()
            if St.phase == "start", St.phase = "idle"; uiresume(fig); end
        end
        function respond(side, how)
            if St.phase ~= "respond", return, end
            St.rt = toc(St.t0);
            St.side = side;  St.how = how;
            St.phase = "idle";
            uiresume(fig);
        end
        function abort()
            St.abort = true;
            if isvalid(fig), uiresume(fig); end
        end
        function closeRequest()
            % 1st request ends the session (the window then closes by itself); a 2nd one
            % closes a window left behind by an interrupted session (ctrl-C)
            if St.abort && isvalid(fig), delete(fig); else, abort(); end
        end
        function onKey(~, evt)
            key = lower(string(evt.Key));
            if key == "escape",  abort();
            elseif key == "space", start();
            elseif key == opts.Keys(1), respond(1, "key");
            elseif key == opts.Keys(2), respond(2, "key");
            end
        end
    end

    function writeTrial(phase, t, k, saidS, how, rt, pick, e)
        resp = ["sh" "s"];  resp = resp(saidS + 1);
        if stim.vowel(k) == "i", words = ["she" "see"]; else, words = ["shoe" "sue"]; end
        if isempty(e), post = nan(1, 5); else, post = [e.mu e.sigma e.muSd e.logSigmaSd e.lapse]; end
        fprintf(fid, "%s\t%s\t%d\t%s\t%s\t%.3f\t%s\t%s\t%d\t%s\t%s\t%.3f\t%s\t%s\t%s\t%.4f\t%.4f\t%.4f\t%.4f\t%.4f\n", participant, phase, t, ...
                stim.talker(k), stim.vowel(k), stim.a(k), stim.filename(k), resp, saidS, words(saidS + 1), how, rt, ...
                opts.ShSide, string(datetime('now', 'Format', 'HH:mm:ss.SSS')), pick, post);
        if phase == "main", nDone = t; else, nPracDone = t; end
    end

    function E = estimates()
        rows = cell(nCond, 1);
        for ci = 1:nCond
            e = psi{ci}.estimate();
            rows{ci} = table(cond.talker(ci), cond.vowel(ci), e.n, stopped(ci), e.mu, e.muSd, e.muCi(1), e.muCi(2), ...
                            e.sigma, e.logSigmaSd, e.sigmaCi(1), e.sigmaCi(2), e.lapse, e.slope, e.width, ...
                            'VariableNames', ["talker" "vowel" "n" "stopped" "mu" "mu_sd" "mu_lo" "mu_hi" ...
                                              "sigma" "logsigma_sd" "sigma_lo" "sigma_hi" "lapse" "slope" "width"]);
        end
        E = vertcat(rows{:});
    end

    function writeInfo()
        f = fopen(infoFile, 'w');
        fprintf(f, "%s\n", jsonencode(info, 'PrettyPrint', true));
        fclose(f);
    end
end

% -------------------------------------------------------------------------
function v = normVowel(v)
switch lower(v)
    case {"i", "ee", "she", "see"},  v = "i";
    case {"u", "oo", "shoe", "sue"}, v = "u";
    otherwise
        error("RunPsiExperiment:badVowel", "Vowels must be ""i"" (she/see) and/or ""u"" (shoe/sue), got ""%s"".", v);
end
end
