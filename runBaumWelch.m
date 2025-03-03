function [gammas,xis,ll] = runBaumWelch(y,x,model,new_sess) 
%[gammas,xis,ll] = runBaumWelch(y, x, model, new_sess)
% Runs the Baum-Welch algorithm to compute latent state posterior
% distributions. Assumes a model of the form by fitGlmHmm.m
%
% Inputs:
%   y               - (1 x NTrials) obsesrvations
%   x               - (NFeatures x NTrials) design matrix
%   model           - GLM-HMM model parameters
%    .w             - (NFeatures x NStates) latent state GLM weights
%    .pi            - (NStates x 1) initial latent state probability
%    .A             - (NStates x NStates) latent state transition matrix
%   new_sess        - (1 x NTrials) logical array with 1s
%                     denoting the start of a new session. If unspecified 
%                     or empty, treats the full set of trials as a single 
%                     session.
%
% Outputs:
%   gammas          - (Nstates x NTrials) Marginal posterior distribution
%   xis             - (Nstates x Nstates x Ntrials) Joint posterior
%                     distribution
%   ll              - log-likelihood of the fit

%% initialize variables
nstates = size(model.w,2);     % number of latent states
T = size(y,2);                 % number of time steps

if ~exist('new_sess','var') || isempty(new_sess)
    new_sess = false(size(y));
    new_sess(1) = true;
end

% data likelihood p(y|z) from emissions model
tmpy = 1./(1+exp(-model.w'*x)); %f(model.w,x(:,1));
py_z = y.*tmpy + (1-y).*(1-tmpy);


%% %%%%%%%%%%%%%%%%%%%%% Forward recursion %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% initialize variables
alphas = nan(nstates,T);       % forward pass alphas
c = nan(T,1);                  % variable to store marginal

for t=1:T
    if new_sess(t)
        alphas(:,t) = model.pi.*py_z(:,t);                      % initial alpha, equation 13.37, reinitialize for new sessions
    else
        %alphas(:,t) = py_z(:,t)'.*sum(alphas(:,t-1).*model.A); % equation 13.36
        alphas(:,t) = py_z(:,t).*(model.A'*alphas(:,t-1));      % equation 13.36
    end
    
    c(t) = sum(alphas(:,t));                                    % store marginal likelihood
    if c(t) == 0, keyboard; end  % this shouldn't happen, check if weights are out of control                           
    alphas(:,t) = alphas(:,t)/c(t);                             % normalize 13.59
end
ll = sum(log(c));                                               % store log-likelihood

%% %%%%%%%%%%%%%%%%%%%%%% Backward recursion %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% initialize variables
betas = nan(nstates,T);                 % backward pass beta
betas(:,end) = ones(nstates,1);         % initial beta (13.39)

% solve for remaining betas
for t = T-1:-1:1
    if new_sess(t+1)
        betas(:,t) = ones(nstates,1);                              % reinitialize backward pass if end of session
    else
        %betas(:,t) = sum(betas(:,t+1)'.*py_z(:,t+1)'.*model.A,2); % equation 13.38
        betas(:,t) = model.A*(betas(:,t+1).*py_z(:,t+1));          % equation 13.38
        betas(:,t) = betas(:,t)/c(t+1);                            % normalize 13.62
    end
end


%% %%%%%%%%%%%%%%%%% Compute posterior distributions %%%%%%%%%%%%%%%%%%%%%%
% gamma - eq. 13.32, 13.64
gammas = alphas.*betas;

% trials to compute xi
% don't use trials at the start of any session to compute the
% transition matrix
Ts = 1:T;
Ts(new_sess) = [];

% xi - eq. 13.43, 13.65 (I'm pretty sure this equation is wrong, I derived
% it and it should be divided, not multiplied, by c(t))
% xis = nan(nstates,nstates,length(Ts));
% for t = 1:length(Ts)
%     %xis(:,:,t) = alphas(:,Ts(t)-1).*py_z(:,Ts(t))'.*model.A.*betas(:,Ts(t))'/c(Ts(t));
%     xis(:,:,t) = (alphas(:,Ts(t)-1)*(py_z(:,Ts(t)).*betas(:,Ts(t)))').*model.A/c(Ts(t));
% end

% NOTE: this isn't the "true" xi, but instead xi summed across time steps
% (the third dimention in the commented definition above). I'm using matrix
% math to compute the summed xi for speed, since we're using the lagrange
% multiplier to optimize the transition matrix in runGlmHmm.m. In a version
% that fits a transition matrix dependent on latent state, the "full" xis
% would need to be computed as commented out above
xis = ((alphas(:,Ts-1)./c(Ts)')*(py_z(:,Ts).*betas(:,Ts))').*model.A;
  
end
        