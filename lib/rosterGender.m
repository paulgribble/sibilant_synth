function g = rosterGender(roster, pid)
% rosterGender  Gender preset for a talker, from the experiment's participants.tsv.
%
%   g = rosterGender(roster, pid)
%
% Returns the talker's `gender_guess` (added to the roster 2026-09-18; a
% guess from the recordings) when that column exists and is non-empty for
% the talker, otherwise the `gender` column (which is a `male` placeholder on
% every row). Used only for the EstimateFormants search-range preset in the
% validation scripts; the synthesis never reads gender.
row = roster.participant == string(pid);
g = "";
if ismember("gender_guess", roster.Properties.VariableNames)
    g = string(roster.gender_guess(row));
end
if isempty(g) || all(ismissing(g) | strlength(g) == 0)
    g = string(roster.gender(row));
end
g = g(1);
end
