%%%-------------------------------------------------------------------
%%% @author Gabriel Fortin
%%% @copyright (C) 2016, Gabriel Fortin
%%% @doc
%%%
%%% @end
%%% Created : 26. Feb 2016 8:32 PM
%%%-------------------------------------------------------------------
-module(top_supervisor).
-author("Gabriel Fortin").

-behaviour(supervisor).


%% API
-export([
    start_link/0,
    start_and_run_pram/1,
    stop_pram/1
]).

%% Supervisor callbacks
-export([
    init/1
]).

-include("../common/defs.hrl").


-define(SUP_NAME, ?MODULE).



%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the supervisor
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link() ->
    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
    % start a supervisor with a static name (singleton supervisor)
    supervisor:start_link({local, ?SUP_NAME}, ?MODULE, []).


start_pram(Args) when is_record(Args, pram_args) ->
    PramChildSpec = {
        _Id = Args#pram_args.instance_name,
        {machine_supervisor, start_link, [Args#pram_args.instance_name]},
        transient,
        2000,
        supervisor,
        [machine_supervisor]
    },
    supervisor:start_child(?SUP_NAME, PramChildSpec).


start_and_run_pram(Args) when is_record(Args, pram_args) ->
    {ok, _PramSupervisorPid} = start_pram(Args),

    % either pid or name can be used to reference the machine
    Name = Args#pram_args.instance_name,

    machine_coordinator:set_input_file(Name, Args#pram_args.input_file_name),
    machine_coordinator:set_output_file(Name, Args#pram_args.output_file_name),
    machine_coordinator:set_program_file(Name, Args#pram_args.program_file_name),
    machine_coordinator:set_memory_model(Name, Args#pram_args.memory_model),
    machine_coordinator:parse_program(Name),
    machine_coordinator:execute_program(Name),
    machine_coordinator:write_output(Name),
    handle_stats_command(Name, Args#pram_args.stats_command),
    ok.


stop_pram(Name) ->
    ok = supervisor:terminate_child(?SUP_NAME, Name),
    ok = supervisor:delete_child(?SUP_NAME, Name),
    ok.



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
-spec(init(Args :: term()) ->
    {ok, {SupFlags :: {RestartStrategy :: supervisor:strategy(),
        MaxR :: non_neg_integer(), MaxT :: non_neg_integer()},
        [ChildSpec :: supervisor:child_spec()]
    }} |
    ignore |
    {error, Reason :: term()}).
init([]) ->
    RestartStrategy = one_for_one,
    MaxRestarts = 10,
    MaxSecondsBetweenRestarts = 3600,

    SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},

    {ok, {SupFlags, [logger_child_spec()]}}.



%%%===================================================================
%%% Internal functions
%%%===================================================================

logger_child_spec() ->
    {
        logger,
        {logger, start_link, []},
        temporary,  % restart strategy: discard on crash and continue work
        100,
        worker,
        [logger]
    }.


handle_stats_command(MachineName, {file, FileName}) ->
    {ok, StatsList} = machine_coordinator:get_stats(MachineName),
    write_stats_to_file(FileName, StatsList);

handle_stats_command(_MachineName, no_stats) ->
    ok.


write_stats_to_file(FileName, StatsList) when is_list(StatsList) ->
    case file:open(FileName, [write]) of
        {error, Reason} ->
            logger:log("could not write stats file \"~p\" for reason: ~p",
                    {?MODULE, 'WARN'}, [FileName, Reason]),
            io:format("WARN: could not write stats file \"~p\" for reason: ~p~n",
                    [FileName, Reason]);
        {ok, File} ->
            [ io:fwrite(File, "~p~n~p~n", [Name, Value]) || {Name, Value} <- StatsList ]
    end.
