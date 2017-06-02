%%%-------------------------------------------------------------------
%%% @author Gabriel Fortin
%%% @copyright (C) 2015, Gabriel Fortin
%%% @doc
%%%
%%% @end
%%% Created : 31. May 2015 10:11 PM
%%%-------------------------------------------------------------------
-module(mem).
-author("Gabriel Fortin").

-include("../common/defs.hrl").


%% public API
-export([
    start_link/1,
    set_memory_model/2,
    deliver_clock_event/1,
    add_var/3,
    read_var/2,
    write_var/2,
    get_all_vars/1,
    get_all_variables/1
]).



-define(RECOGNISED_MEMORY_MODELS,
    [none, 'EREW', 'CREW', 'CRCW common', 'CRCW arbitrary', 'CRCW priority']).



start_link(MemoryModel) ->
    true = lists:member(MemoryModel, ?RECOGNISED_MEMORY_MODELS),
    Module = ?MEM_IMPL_MODULE,
    gen_server:start_link(Module, MemoryModel, _Opts=[]).

set_memory_model(Mem, Model) ->
    logger:log("set memory model (API): ~p", ?MODULE, [Model]),
    case lists:member(Model, ?RECOGNISED_MEMORY_MODELS) of
        false ->
            throw({invalid_arg, {got, Model}, {expected, one_of, ?RECOGNISED_MEMORY_MODELS}});
        true ->
            case gen_server:call(Mem, {set_model, Model}) of
                {err, Error} ->
                    throw(Error);
                ok ->
                    ok
            end
    end.


deliver_clock_event(Mem) when is_pid(Mem) ->
    logger:log("notify clock event (API)", ?MODULE),
    case gen_server:call(Mem, tick, ?TIMEOUT) of
        {err, memory_model_violation, Model, Action, Violations} ->
            throw({memory_model_violation, {current_model, Model}, {violations, Violations}});
        ok ->
            ok
    end.

% TODO: get rid of those bizarre tuples from arguments of 'mem' interface functions
add_var({VarType, VarName}, Mem, VarProperties)
        when is_pid(Mem), is_list(VarProperties) ->
    logger:log("add_var (API): {~W, ~p}, ~110p", ?MODULE, [VarType, 3, VarName, VarProperties]),
    case gen_server:call(Mem, {add_var, VarType, VarName, VarProperties}, ?TIMEOUT) of
        {err, var_already_defined} ->
            throw({var_already_defined, VarName});
        ok ->
            ok
    end.

read_var(VarName, Mem) when is_pid(Mem) ->
    logger:log("read var (API): ~p", ?MODULE, [VarName]),
    case gen_server:call(Mem, {read_var, VarName}, ?TIMEOUT) of
        {err, no_such_global_var} ->
            throw({no_such_global_var, {var_name, VarName}});
        {err, not_initialised} ->
            throw({not_initialised, {var_name, VarName}});
        {err, invalid_memory_access} ->
            throw({invalid_memory_access, {var_name, VarName}});
        {ok, {VarType, VarValue}} ->
            Result = {ok, {VarType, VarValue}},
            logger:log("=> ~110p", ?MODULE, [Result]),
            Result
    end.

write_var({VarName, Value}, Mem) when is_pid(Mem) ->
    logger:log("write var (API): {~150p, ~150p}", ?MODULE, [VarName, Value]),
    case gen_server:call(Mem, {write_var, VarName, Value}, ?TIMEOUT) of
        {err, no_such_global_var} ->
            throw({no_such_global_var, VarName});
        {err, invalid_memory_access} ->
            throw({invalid_memory_access, {var_name, VarName}});
        ok ->
            ok
    end.

get_all_vars(Mem) when is_pid(Mem) ->
    case gen_server:call(Mem, get_all_vars, ?TIMEOUT) of
        {ok, AllVars} ->
            logger:log("get all vars (API): 'AllVars':", ?MODULE),
            logger:log("      ~110p", ?MODULE, [AllVars]),
            {ok, AllVars}
    end.

get_all_variables(Mem) when is_pid(Mem) ->
    case gen_server:call(Mem, get_all_variables, ?TIMEOUT) of
        {ok, AllVariables} ->
            {ok, AllVariables}
    end.

