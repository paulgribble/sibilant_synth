function [T, dataFile] = RunPerceptionExperiment(participant, opts)
% RunPerceptionExperiment  Two-alternative identification of tokens on the /sh/ -- /s/ continuum.
%
%   RunPerceptionExperiment("P01")                                   % she/see, a = 0:0.1:1, 10 reps
%   RunPerceptionExperiment("P01", 'A', 0:0.2:1, 'Reps', 15)
%   RunPerceptionExperiment("P01", 'Vowels', "u")                    % shoe/sue
%   RunPerceptionExperiment("P01", 'Vowels', ["i" "u"])              % both, intermixed
%   RunPerceptionExperiment("P01", 'Practice', 0)                    % no practice block
%   [T, dataFile] = RunPerceptionExperiment("sim", 'Simulate', [0.45 0.06 0.02])
%
% On every trial one synthesised token is played and the participant says
% whether it began with /sh/ or /s/, by clicking one of two buttons or
% pressing a key (F = left button, J = right button by default). The
% stimulus list is every Talker x Vowel x A combination, Reps times: each
% repetition is one block holding every combination once, shuffled afresh,
% so the levels are spread evenly over the session. Every trial is written
% to a .tsv file as soon as the response is made.
%
% The session opens with a PRACTICE block of the clear endpoint tokens
% (a = 0 and a = 1 of every Talker x Vowel, whatever A is; Practice shuffled
% repetitions of them), so the participant learns the task and the keys on
% unambiguous words. It runs exactly like the main trials (no feedback) and
% is followed by a screen announcing the main part. Practice trials are
% saved in the same file with phase = "practice"; FitPsychometric ignores
% them. The experimenter sees in the command window how many were answered
% as expected.
%
% The buttons read she / see for 'Vowels', "i", shoe / sue for "u", and
% "she / shoe" / "see / sue" when the two vowels are mixed.
%
% STIMULI are WAV files, never synthesised during the trials: before the
% first trial PreparePerceptionStimuli looks in StimDir for
% <talker>_<vowel>_a<a>.wav (the WriteSibilantContinuum naming) and
% synthesises in one batch whatever is missing; all WAVs are then read into
% memory. Playback is at the level of the files (vowel RMS -20 dBFS); set the
% listening level with the system volume before the participant starts.
%
% TRIAL: buttons greyed, ItiS of silence, the token plays, the buttons
% become active at the END of the token (earlier clicks and key presses are
% ignored, which also stops a held-down key from answering the next trial),
% the response is shown for 150 ms. There is no feedback and no time limit.
% rt_s is measured from the start of playback (so it includes the token and
% the unknown audio output latency; treat it as approximate). ESCAPE or
% closing the window ends the session early; the trials done so far are
% already in the file. The window closes by itself when the session ends;
% if one is ever left behind (session interrupted with ctrl-C), click its
% close box twice.
%
% Options (name, value):
%   A           continuum levels, each in [0, 1] with at most 3 decimals
%               (default 0:0.1:1)
%   Reps        repetitions of every Talker x Vowel x A combination (default 10)
%   Practice    repetitions of each endpoint (a = 0, a = 1) per Talker x Vowel
%               in the practice block (default 3, i.e. 6 trials for one
%               talker and vowel; 0 = no practice)
%   Vowels      "i" (she/see, default), "u" (shoe/sue) or ["i" "u"] (mixed)
%   Talkers     one or more talker ids (default "pert4P17"; see
%               SynthSibilantTalkers). With several, they are intermixed.
%   StimDir     folder of the WAVs (default ../stimuli next to this folder)
%   DataDir     where the data file goes (default data/ in this folder)
%   Keys        [left right] response keys (default ["f" "j"])
%   ShSide      "left" (default) or "right": the side of the /sh/ button and
%               key, for counterbalancing over participants
%   ItiS        silence between the response and the next token, s (default 0.75)
%   BreakEvery  offer a self-paced break every this many main trials (default 0 = never)
%   Seed        seed of the trial order ([] = from the clock; the one used is
%               saved in the .json file). The main order for a given Seed
%               does not depend on Practice.
%   Regenerate  true = synthesise the needed WAVs again even if they exist
%   WindowState "maximized" (default), "fullscreen" or "normal"
%   Simulate    [] (default) = run the experiment. [pse sigma lapse] = no
%               window, no sound: a simulated listener answers "s" with
%               probability lapse + (1 - 2 lapse) / (1 + exp(-(a - pse)/sigma)),
%               practice trials included.
%               For checking the pipeline and FitPsychometric.
%
% Output files, in DataDir:
%   <participant>_<yyyymmdd_HHMMSS>.tsv   one row per completed trial:
%       participant, phase (practice / main), trial (counted within the
%       phase), block (repetition number; 0 in practice), talker, vowel, a,
%       filename, response ("sh" or "s"), resp_s (0 = /sh/, 1 = /s/), word
%       (the word chosen: she / see / shoe / sue), input (key / button /
%       sim), rt_s, sh_side, time (HH:mm:ss.SSS at the response)
%   <participant>_<yyyymmdd_HHMMSS>.json  the options, the trial-order seed,
%       the stimulus folder and whether the session was completed
%
% Returns the trial table T and the path of the .tsv. Analyse with
% FitPsychometric(dataFile).
%
% See also FitPsychometric, PreparePerceptionStimuli, WriteSibilantContinuum.

arguments
    participant (1,1) string
    opts.A (1,:) double {mustBeInRange(opts.A, 0, 1)} = 0:0.1:1
    opts.Reps (1,1) double {mustBeInteger, mustBePositive} = 10
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
    error("RunPerceptionExperiment:badId", "participant may contain only letters, digits and ""-"", got ""%s"".", participant);
end
if any(abs(opts.A - round(opts.A, 3)) > 1e-9)
    error("RunPerceptionExperiment:badA", "A levels may have at most 3 decimals (they name the WAV files).");
end
A = unique(round(opts.A, 3));
vowels = unique(arrayfun(@normVowel, opts.Vowels), 'stable');
talkers = unique(opts.Talkers, 'stable');
opts.Keys = lower(opts.Keys);
if opts.Keys(1) == opts.Keys(2) || any(ismember(opts.Keys, ["escape" "space"]))
    error("RunPerceptionExperiment:badKeys", "Keys must be two different keys, not escape or space.");
end
simulate = ~isempty(opts.Simulate);
if simulate && numel(opts.Simulate) ~= 3
    error("RunPerceptionExperiment:badSimulate", "Simulate must be [pse sigma lapse].");
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
stimA = A;
if opts.Practice > 0, stimA = unique([A 0 1]); end      % the practice block uses the endpoints, whatever A is
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

% ------------------------------------------------------------- trial order
seed = opts.Seed;
if isempty(seed), seed = randi(RandStream('mt19937ar', 'Seed', 'shuffle'), 2^31 - 2); end
rs = RandStream('mt19937ar', 'Seed', seed);
iMain = find(ismember(stim.a, A));                       % main: every talker x vowel x A, one shuffled block per repetition
iPrac = find(stim.a == 0 | stim.a == 1);                 % practice: the endpoints of every talker x vowel, same scheme
order = zeros(numel(iMain), opts.Reps);
for r = 1:opts.Reps, order(:, r) = iMain(randperm(rs, numel(iMain))); end
block = repmat(1:opts.Reps, numel(iMain), 1);
pracOrder = zeros(numel(iPrac), opts.Practice);          % drawn after the main order, so Practice does not change it
for r = 1:opts.Practice, pracOrder(:, r) = iPrac(randperm(rs, numel(iPrac))); end
nTrials = numel(order);                                  % main trials
nPrac = numel(pracOrder);
L = table([repmat("practice", nPrac, 1); repmat("main", nTrials, 1)], [(1:nPrac)'; (1:nTrials)'], ...
          [zeros(nPrac, 1); block(:)], [pracOrder(:); order(:)], 'VariableNames', ["phase" "trial" "block" "stim"]);

% ------------------------------------------------------------- output files
if ~isfolder(opts.DataDir), mkdir(opts.DataDir); end
stamp = string(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
dataFile = fullfile(opts.DataDir, participant + "_" + stamp + ".tsv");
infoFile = fullfile(opts.DataDir, participant + "_" + stamp + ".json");
info = struct('participant', participant, 'started', string(datetime('now')), 'completed', false, ...
              'nTrialsPlanned', nTrials, 'nTrialsDone', 0, 'nPracticePlanned', nPrac, 'nPracticeDone', 0, ...
              'A', A, 'reps', opts.Reps, 'practiceReps', opts.Practice, ...
              'vowels', vowels, 'talkers', talkers, 'stimDir', opts.StimDir, 'keys', opts.Keys, ...
              'shSide', opts.ShSide, 'itiS', opts.ItiS, 'breakEvery', opts.BreakEvery, ...
              'orderSeed', seed, 'simulate', opts.Simulate);
writeInfo();
fid = fopen(dataFile, 'w');                              % 'w' flushes after every write
if fid < 0, error("RunPerceptionExperiment:noFile", "Cannot write %s.", dataFile); end
closeFile = onCleanup(@() fclose(fid));
fprintf(fid, "participant\tphase\ttrial\tblock\ttalker\tvowel\ta\tfilename\tresponse\tresp_s\tword\tinput\trt_s\tsh_side\ttime\n");

% ---------------------------------------------------------------- run
St = struct('phase', "idle", 'abort', false, 'side', 0, 'how', "", 'rt', NaN, 't0', uint64(0));
nDone = 0;                                               % main trials answered
nPracDone = 0;
if simulate
    for it = 1:height(L)
        p = opts.Simulate(3) + (1 - 2 * opts.Simulate(3)) / (1 + exp(-(stim.a(L.stim(it)) - opts.Simulate(1)) / opts.Simulate(2)));
        writeTrial(it, rand(rs) < p, "sim", NaN);
    end
else
    runGui();
end

info.completed = nDone == nTrials;
info.nTrialsDone = nDone;
info.nPracticeDone = nPracDone;
info.finished = string(datetime('now'));
writeInfo();
clear closeFile
T = readtable(dataFile, 'FileType', 'text', 'Delimiter', '\t', 'TextType', 'string');
fprintf("%d of %d trials saved to %s\n", nDone, nTrials, dataFile);
if nPracDone > 0
    P = T(T.phase == "practice", :);
    fprintf("  practice: %d of %d endpoint tokens answered as expected (a = 0 ""sh"", a = 1 ""s"")\n", sum(P.resp_s == P.a), height(P));
end
if nDone > 0
    Tm = T(T.phase == "main", :);
    [g, lev] = findgroups(Tm.a);
    fprintf("  a        %s\n  p(""s"")   %s\n", sprintf("%6.3f", lev), sprintf("%6.2f", splitapply(@mean, Tm.resp_s, g)));
end

% =========================================================================
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
            runTrials();
        catch err
            if isvalid(fig), delete(fig); end
            rethrow(err);
        end
        if isvalid(fig), delete(fig); end

        % ---- nested: the session, screens and callbacks
        function runTrials()
            pracNote = "";  startText = "Start (space bar)";
            if nPrac > 0
                pracNote = sprintf("\n\nFirst, %d practice trials.", nPrac);
                startText = "Start the practice (space bar)";
            end
            waitStart(sprintf("You will hear one word on each trial. Was it ""%s"" or ""%s""?\n\n" + ...
                              """%s"": press %s or click the left button\n""%s"": press %s or click the right button\n\n" + ...
                              "Answer once the word has ended. If you are unsure, go with your first impression." + ...
                              pracNote, ...
                              sideLabel(1), sideLabel(2), sideLabel(1), upper(opts.Keys(1)), sideLabel(2), upper(opts.Keys(2))), ...
                      startText);

            for i = 1:height(L)
                if St.abort, break, end
                t = L.trial(i);
                if L.phase(i) == "main" && t == 1 && nPrac > 0
                    waitStart(sprintf("That was the practice.\n\nThe main part starts now: %d trials, same task.\n" + ...
                                      "Some words will be less clear than others; just give your best answer.", nTrials), "Start (space bar)");
                    if St.abort, break, end
                end
                if L.phase(i) == "main" && opts.BreakEvery > 0 && t > 1 && mod(t - 1, opts.BreakEvery) == 0
                    waitStart(sprintf("Time for a short break.\n%d of %d trials done.", t - 1, nTrials), "Continue (space bar)");
                    if St.abort, break, end
                end
                k = L.stim(i);
                if L.phase(i) == "main", prog.Text = sprintf("%d / %d", t, nTrials);
                else,                    prog.Text = sprintf("practice %d / %d", t, nPrac);
                end
                pause(opts.ItiS);
                if St.abort, break, end

                player = audioplayer(wav{k}, wavFs(k));      % held in this variable until the next trial, so it is not deleted mid-playback
                St.phase = "play";
                play(player);
                St.t0 = tic;
                pause(numel(wav{k}) / wavFs(k));             % callbacks run, but responses are ignored until the token ends
                if St.abort, break, end

                St.phase = "respond";
                set(btn, 'Enable', 'on');
                uiwait(fig);
                if St.abort || ~isvalid(fig), break, end

                writeTrial(i, sideSound(St.side) == "s", St.how, St.rt);
                btn(St.side).BackgroundColor = chosen;
                pause(0.15);
                if St.abort || ~isvalid(fig), break, end
                btn(St.side).BackgroundColor = idle;
                set(btn, 'Enable', 'off');
            end
            if isvalid(fig) && ~St.abort
                msg.Text = "Finished. Thank you!";
                prog.Text = "";
                pause(2);
            end
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

    function writeTrial(i, saidS, how, rt)
        k = L.stim(i);
        resp = ["sh" "s"];  resp = resp(saidS + 1);
        if stim.vowel(k) == "i", words = ["she" "see"]; else, words = ["shoe" "sue"]; end
        fprintf(fid, "%s\t%s\t%d\t%d\t%s\t%s\t%.3f\t%s\t%s\t%d\t%s\t%s\t%.3f\t%s\t%s\n", participant, L.phase(i), L.trial(i), L.block(i), ...
                stim.talker(k), stim.vowel(k), stim.a(k), stim.filename(k), resp, saidS, words(saidS + 1), how, rt, ...
                opts.ShSide, string(datetime('now', 'Format', 'HH:mm:ss.SSS')));
        if L.phase(i) == "main", nDone = L.trial(i); else, nPracDone = L.trial(i); end
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
        error("RunPerceptionExperiment:badVowel", "Vowels must be ""i"" (she/see) and/or ""u"" (shoe/sue), got ""%s"".", v);
end
end
