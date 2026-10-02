classdef PsiMethod < handle
% PsiMethod  Adaptive trial placement on a psychometric function (Psi method, Kontsevich & Tyler 1999).
%
%   psi = PsiMethod(0:0.01:1);         % the levels a trial may be placed at
%   a = psi.next();                    % the most informative level now
%   psi.update(a, saidS);              % the response, 1 = "s", 0 = "sh"
%   e = psi.estimate();                % posterior mean and SD of the boundary and log sigma
%
% The listener is modelled as P("s" | a) = lambda + (1 - 2 lambda) F((a - mu)/sigma),
% F logistic (default) or cumulative normal, on a grid of mu x log(sigma) x
% lambda with a uniform prior. Every response updates the posterior over the
% grid by Bayes' rule. next() returns the level that minimises the expected
% entropy of the posterior over (mu, log sigma) after the next response, the
% lapse rate marginalised out (the psi-marginal rule of Prins 2013), i.e.
% the level expected to tell most about the boundary and the slope. In
% practice it alternates between the current boundary estimate and points
% about one sigma either side of it. The rule is greedy (one trial ahead)
% and deterministic: the same responses give the same sequence.
%
% Options (name, value):
%   MuRange     [lo hi] of the mu grid (default [0 1])
%   NMu         grid points in mu (default 201, step 0.005)
%   SigmaRange  [lo hi] of the sigma grid, log-spaced (default [0.005 0.5])
%   NSigma      grid points in log sigma (default 41)
%   Lapse       lapse rates on the grid (default [0 0.01 0.02 0.04 0.08])
%   Function    "logistic" (default) or "normal"
%   Prior       NMu x NSigma x numel(Lapse) array of prior weights (default uniform)
%
% Methods:
%   a = next()          level to test next (also returns the expected entropy per level)
%   update(a, r)        record response r (1 = "s", 0 = "sh") to level a (one of the levels)
%   e = estimate()      struct: n, mu, muSd, muCi, sigma, logSigmaSd, sigmaCi, lapse,
%                       slope, width. Means and SDs of the marginal posteriors;
%                       sigma = exp(mean log sigma); the Ci are 95 % credible
%                       intervals at grid resolution; slope = dP/da at mu;
%                       width = a(F = 0.75) - a(F = 0.25)
%   p = marginal(dim)   marginal posterior over "mu", "sigma" or "lapse"
%
% Properties: levels, mu, sigma, lapse, func, posterior (NMu x NSigma x
% NLapse), history (n x 2: level, response).
%
% Kontsevich LL, Tyler CW (1999) Vision Res 39:2729-2737.
% Prins N (2013) J Vis 13(7):3.
%
% See also RunPsiExperiment, FitPsychometric.

properties (SetAccess = private)
    levels      % candidate levels, row
    mu          % grid, row
    sigma       % grid, row (log-spaced)
    lapse       % grid, row
    func        % "logistic" or "normal"
    posterior   % NMu x NSigma x NLapse, sums to 1
    history = zeros(0, 2)   % [level response] per trial
end
properties (Access = private)
    lik         % numel(levels) x numel(posterior): P("s" | level, theta)
end

methods
    function obj = PsiMethod(levels, opts)
        arguments
            levels (1,:) double
            opts.MuRange (1,2) double = [0 1]
            opts.NMu (1,1) double {mustBeInteger, mustBeGreaterThan(opts.NMu, 1)} = 201
            opts.SigmaRange (1,2) double {mustBePositive} = [0.005 0.5]
            opts.NSigma (1,1) double {mustBeInteger, mustBeGreaterThan(opts.NSigma, 1)} = 41
            opts.Lapse (1,:) double {mustBeInRange(opts.Lapse, 0, 0.5, "exclude-upper")} = [0 0.01 0.02 0.04 0.08]
            opts.Function (1,1) string {mustBeMember(opts.Function, ["logistic" "normal"])} = "logistic"
            opts.Prior double = []
        end
        obj.levels = reshape(unique(levels), 1, []);
        obj.mu = linspace(opts.MuRange(1), opts.MuRange(2), opts.NMu);
        obj.sigma = logspace(log10(opts.SigmaRange(1)), log10(opts.SigmaRange(2)), opts.NSigma);
        obj.lapse = reshape(unique(opts.Lapse), 1, []);
        obj.func = opts.Function;
        [M, S, L] = ndgrid(obj.mu, obj.sigma, obj.lapse);
        z = (obj.levels(:) - M(:)') ./ S(:)';
        if obj.func == "logistic", F = 1 ./ (1 + exp(-z)); else, F = 0.5 * erfc(-z / sqrt(2)); end
        obj.lik = L(:)' + (1 - 2 * L(:)') .* F;
        if isempty(opts.Prior)
            P = ones(size(M));
        else
            if ~isequal(size(opts.Prior), size(M)) || any(opts.Prior(:) < 0)
                error("PsiMethod:prior", "Prior must be a non-negative %d x %d x %d array.", size(M, 1), size(M, 2), size(M, 3));
            end
            P = opts.Prior;
        end
        obj.posterior = P / sum(P(:));
    end

    function [a, eh] = next(obj)
        % level minimising the expected entropy of the (mu, log sigma) posterior
        P = obj.posterior(:);
        nL = numel(obj.levels);  nMS = numel(obj.mu) * numel(obj.sigma);  nLap = numel(obj.lapse);
        p1 = min(max(obj.lik * P, eps), 1 - eps);        % P("s" | level) under the current posterior
        eh = zeros(nL, 1);
        for r = 0:1
            if r == 1, Q = obj.lik .* P';  pr = p1;  else, Q = (1 - obj.lik) .* P';  pr = 1 - p1;  end
            Q = sum(reshape(Q ./ pr, nL, nMS, nLap), 3);   % posterior after response r, lapse marginalised
            eh = eh - pr .* sum(Q .* log(Q + realmin), 2);
        end
        [~, i] = min(eh);
        a = obj.levels(i);
    end

    function update(obj, a, r)
        [d, i] = min(abs(obj.levels - a));
        if d > 1e-6, error("PsiMethod:level", "%.4f is not one of the levels.", a); end
        if r, l = obj.lik(i, :); else, l = 1 - obj.lik(i, :); end
        P = obj.posterior(:) .* l(:);
        obj.posterior = reshape(P / sum(P), size(obj.posterior));
        obj.history(end + 1, :) = [obj.levels(i), logical(r)];
    end

    function p = marginal(obj, dim)
        switch string(dim)
            case "mu",    p = reshape(sum(obj.posterior, [2 3]), 1, []);
            case "sigma", p = reshape(sum(obj.posterior, [1 3]), 1, []);
            case "lapse", p = reshape(sum(obj.posterior, [1 2]), 1, []);
            otherwise, error("PsiMethod:dim", "dim must be ""mu"", ""sigma"" or ""lapse"".");
        end
    end

    function e = estimate(obj)
        pm = obj.marginal("mu");  ps = obj.marginal("sigma");  pl = obj.marginal("lapse");
        ls = log(obj.sigma);
        e.n = size(obj.history, 1);
        e.mu = sum(pm .* obj.mu);
        e.muSd = sqrt(sum(pm .* (obj.mu - e.mu).^2));
        e.muCi = credible(obj.mu, pm);
        mls = sum(ps .* ls);
        e.sigma = exp(mls);
        e.logSigmaSd = sqrt(sum(ps .* (ls - mls).^2));
        e.sigmaCi = credible(obj.sigma, ps);
        e.lapse = sum(pl .* obj.lapse);
        if obj.func == "logistic", dens = 0.25;  e.width = 2 * log(3) * e.sigma;
        else,                      dens = 1 / sqrt(2 * pi);  e.width = 2 * 0.674489750196082 * e.sigma;
        end
        e.slope = (1 - 2 * e.lapse) * dens / e.sigma;
    end
end
end

% -------------------------------------------------------------------------
function ci = credible(x, p)
% 95 % interval of a discrete marginal, at grid resolution
c = cumsum(p);
ci = [x(find(c >= 0.025, 1)), x(find(c >= 0.975, 1))];
end
