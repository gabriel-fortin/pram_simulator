%%%-------------------------------------------------------------------
%%% @author Gabriel Fortin
%%% @copyright (C) 2016, Gabriel Fortin
%%% @doc
%%%
%%% @end
%%% Created : 27. Feb 2016 9:40 AM
%%%-------------------------------------------------------------------
-module(machine_supervisor).
-author("Gabriel Fortin").

-behaviour(supervisor).


-include("../common/defs.hrl").

%% API
-export([
    start_link/1
]).

%% Supervisor callbacks
-export([
    init/1
]).



%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the supervisor
%%
%% @end
%%--------------------------------------------------------------------
-spec start_link(_MachineName) -> {ok, Pid} | ignore | {error, Reason}
    when    Pid     :: pid(),
            Reason  :: term().
start_link(MachineName) ->
    % start a nameless supervisor
    ImplModule = ?MODULE,
    supervisor:start_link(ImplModule, {arg, MachineName}).



%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a supervisor is started using supervisor:start_link/[2,3],
%% this function is called by the new process to find out about
%% restart strategy, maximum restart frequency and child
%% specifications.
%%
%% @end
%%--------------------------------------------------------------------
-spec init(Args) -> {ok, {SupFlags, ChildSpecs}} | ignore | {error, Reason}
    when    Args        :: {arg, _MachineName},
            SupFlags    :: {supervisor:strategy(), non_neg_integer(), non_neg_integer()},
            ChildSpecs  :: [supervisor:child_spec()],
            Reason      :: term().
init({arg, MachineName}) ->
    RestartStrategy = one_for_all,
    MaxRestarts = 1,
    MaxSecondsBetweenRestarts = 3600,

    SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},

    Restart = permanent,
    Shutdown = 2000,
    Type = worker,

    % starting only the 'machine_coordinator' which will add other children by itself
    CoordinatorArgs = [MachineName, _MachineSupervisor=self()],
    CoordinatorChildSpec = {
        MachineName,
        {_Mod=machine_coordinator, _Fun=start_link, CoordinatorArgs},
        Restart,
        Shutdown,
        Type,
        [machine_coordinator]
    },

    {ok, {SupFlags, [CoordinatorChildSpec]}}.

