function ids = SynthSibilantTalkers(model)
% SynthSibilantTalkers  List the talker ids available to SynthSibilant.
%
%   ids = SynthSibilantTalkers()          % from sibilant_model.mat next to SynthSibilant.m
%   ids = SynthSibilantTalkers(model)     % from a model struct or a .mat path
%
% Returns a string array of participant ids, e.g. "pert6P02".

arguments
    model = ""
end
if isstruct(model)
    ids = model.talkerIds;
    return
end
if model == ""
    model = fullfile(fileparts(mfilename('fullpath')), "sibilant_model.mat");
end
if ~isfile(model)
    error("SynthSibilantTalkers:noModel", "Model file not found: %s (run BuildSibilantModel).", model);
end
S = load(model, 'model');
ids = S.model.talkerIds;
end
