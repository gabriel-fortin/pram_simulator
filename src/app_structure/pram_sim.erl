%%%-------------------------------------------------------------------
%%% @author Gabriel Fortin
%%% @copyright (C) 2016, Gabriel Fortin
%%% @doc
%%%
%%% @end
%%% Created : 26. Feb 2016 8:30 PM
%%%-------------------------------------------------------------------
-module(pram_sim).
-author("Gabriel Fortin").

-behaviour(application).


-include("../common/defs.hrl").

%% API
-export([
    start_and_run_pram/5, start_and_run_pram/6,
    start_from_env/0,
    disable_logs/0,
    stop_pram/1
]).

%% Application callbacks
-export([
    start/2,
    stop/1
]).



%%%===================================================================
%%% API functions
%%%===================================================================

% TODO: add start_pram/1 function and allow to provide arguments one by one

start_and_run_pram(Name, ProgramFileName, InputFileName, OutputFileName, MemoryModel) ->
    start_and_run_pram(Name, ProgramFileName, InputFileName, OutputFileName, MemoryModel, no_stats).

start_and_run_pram(Name, ProgramFileName, InputFileName, OutputFileName, MemoryModel,
    StatsCommand) ->
    Args = #pram_args{
        instance_name = id(Name),
        program_file_name = ProgramFileName,
        input_file_name = InputFileName,
        output_file_name = OutputFileName,
        memory_model = MemoryModel,
        stats_command = StatsCommand
    },
    io:format("~n == ARGS~n~p~n~n", [Args]),
    top_supervisor:start_and_run_pram(Args),
    top_supervisor:stop_pram(Name).


start_from_env() ->
    print_env(),
    Name = pram_by_env,
    AppName = pram_sim,

    {ok, Program} = application:get_env(AppName, program_file),
    {ok, Input} = application:get_env(AppName, input_file),
    {ok, Output} = application:get_env(AppName, output_file),
    {ok, MemModel} = application:get_env(AppName, memory_model),
    StatsCommand = case application:get_env(AppName, stats_file) of
            {ok, StatsFile} ->
                {file, StatsFile};
            undefined ->
                no_stats
        end,

    start_and_run_pram(Name, Program, Input, Output, MemModel, StatsCommand).


disable_logs() ->
    logger:set_filter_mode(include),
    logger:filter_set([]).


stop_pram(Name) ->
    top_supervisor:stop_pram(id(Name)).



%%%===================================================================
%%% Application callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called whenever an application is started using
%% application:start/[1,2], and should start the processes of the
%% application. If the application is structured according to the OTP
%% design principles as a supervision tree, this means starting the
%% top supervisor of the tree.
%%
%% @end
%%--------------------------------------------------------------------
-spec(start(StartType :: normal | {takeover, node()} | {failover, node()},
    StartArgs :: term()) ->
    {ok, pid()} |
    {ok, pid(), State :: term()} |
    {error, Reason :: term()}).
start(normal, _StartArgs=[]) ->
    case top_supervisor:start_link() of
        {ok, Pid} ->
            {ok, Pid};
        Error ->
            Error
    end.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called whenever an application has stopped. It
%% is intended to be the opposite of Module:start/2 and should do
%% any necessary cleaning up. The return value is ignored.
%%
%% @end
%%--------------------------------------------------------------------
-spec(stop(State :: term()) -> term()).
stop(_State) ->
    ok.



%%%===================================================================
%%% Internal functions
%%%===================================================================

id(Name) when is_atom(Name) ->
    % must be an atom because OTP calls erlang:whereis/1
    Name.


print_env() ->
    Envs_2 = [
        application:get_env(pram_sim, program_file),
        application:get_env(pram_sim, input_file),
        application:get_env(pram_sim, output_file),
        application:get_env(pram_sim, memory_model)
    ],
    io:format("ENV:~n  ~p~n", [Envs_2]).
