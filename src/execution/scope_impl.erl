%%%-------------------------------------------------------------------
%%% @author Gabriel Fortin
%%% @copyright (C) 2015, Gabriel Fortin
%%% @private
%%% @doc
%%%
%%% @end
%%% Created : 27. Jul 2015 9:07 PM
%%%-------------------------------------------------------------------
-module(scope_impl).
-author("Gabriel Fortin").


-behaviour(gen_server).

-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).


-include("../common/ast.hrl").
-include("../common/defs.hrl").



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%  TYPES AND STRUCTURES
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-record(scope, {
    framesStack    :: [],  % list of frames representing nested scopes
    funs,                  % flat structure for functions
    globalMem      :: pid(),
    depth          :: non_neg_integer()  % scopes' depth, equals to "length(vars)"
}).



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%  GEN_SERVER CALLBACKS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% called by "gen_server:start_link" and "gen_server:start"
%% @hidden
init(_Args=[]) ->
    State = #scope{
        framesStack = [],
        funs = dict:new(),
        depth = 0},
    {ok, State};
init(_Args={scope_to_copy, ScopeToCopy}) ->
    State = util:send_sync(ScopeToCopy, copy_internal_state, ?TIMEOUT),
    {ok, State}.


% called by "gen_server:call"
%% @hidden
handle_call(open_frame, _From, S) ->
    case internal_openFrame(S) of
        {ok, NewScope} ->
            {reply, ok, NewScope}
    end;

handle_call(close_frame, _From, S) ->
    case internal_closeFrame(S) of
        {err, no_open_scopes} ->
            {reply, {err, no_open_scopes}, S};
        {ok, NewScope} ->
            {reply, ok, NewScope}
    end;

handle_call({add_fun, Fun}, _From, S) ->
    case internal_add_fun(S, Fun) of
        {err, fun_already_defined_in_scope} ->
            {reply, {err, fun_already_defined_in_scope}, S};
        {ok, NewScope} ->
            {reply, ok, NewScope}
    end;

handle_call({get_fun, FunName}, _From, S) ->
    case internal_get_fun(S, FunName) of
        {err, not_in_scope} ->
            {reply, {err, not_in_scope}, S};
        {ok, Fun} ->
            {reply, {ok, Fun}, S}
    end;

handle_call({add_var, VarAddr, VarType, VarProperties}, _From, S) ->
    case internal_add_var(S, VarAddr, VarType, VarProperties) of
        {err, no_open_scopes} ->
            {reply, {err, no_open_scopes}, S};
        {err, var_already_defined_in_scope} ->
            {reply, {err, var_already_defined_in_scope}, S};
        {ok, NewScope} when is_record(NewScope, scope) ->
            {reply, ok, NewScope}
    end;

handle_call({read_var, VarName}, _From, S) ->
    case internal_read_var(S, VarName) of
        {err, not_in_scope} ->
            {reply, {err, not_in_scope}, S};
        {ok, global_var} ->
            {reply, {ok, global_var}, S};
        {ok, Type, Value} ->
            {reply, {ok, Value, Type}, S}
    end;

handle_call({write_var, VarName, Value}, _From, S) ->
    case internal_write_var(VarName, Value, S#scope.framesStack) of
        {err, not_in_scope} ->
            {reply, {err, not_in_scope}, S};
        {err, global_var} ->
            {reply, {err, global_var}, S};
        {err, const_var} ->
            {reply, {err, const_var}, S};
        {ok, FramesStack_1} ->
            Scope_1 = S#scope{framesStack = FramesStack_1},
            {reply, ok, Scope_1}
    end;

handle_call(AnythingElse, _From, S) ->
    io:format("ERROR: scope: received an unrecognized gen_server callback~n"
            ++"       request: ~p~n", [AnythingElse]),
    {noreply, S}.


%% @hidden
handle_cast(Request, State) ->
    io:format("ERROR: scope: unsupported: received a cast in a gen_server callback~n"
    ++"       cast request content: ~p~n", [Request]),
    {noreply, State}.


%% @hidden
handle_info({Sender, copy_internal_state}, State) ->
    util:reply(Sender, State),
    {noreply, State};
handle_info(Info, State) ->
    io:format("ERROR: scope: unsupported: received an info in a gen_server callback~n"
    ++"       info content: ~p~n", [Info]),
    {noreply, State}.


%% @hidden
terminate(_Reason, _State) ->
    logger:log("terminating", ?MODULE),
    ok.


%% @hidden
code_change(_OldVsn, _State, _Extra) ->
    {error, not_supported}.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%  HELPER FUNCTIONS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%% @private
internal_openFrame(S) ->
    % prepend a new, empty dictionary
    FramesStack_1 = [dict:new() | S#scope.framesStack],
    Depth = S#scope.depth + 1,
    {ok, S#scope{framesStack = FramesStack_1, depth = Depth}}.


%% @private
internal_closeFrame(#scope{framesStack = []})  ->
    {err, no_open_scopes};
internal_closeFrame(S=#scope{}) ->
    [_ | NestedFrames] = S#scope.framesStack,
    Depth = S#scope.depth - 1,
    {ok, S#scope{framesStack = NestedFrames, depth = Depth}}.


%% @private
internal_add_fun(S=#scope{}, F=#rFunctionDef{}) ->
    FunDict = S#scope.funs,
    Name = F#rFunctionDef.ident,
    case dict:is_key(Name, FunDict) of
        true ->
            {err, fun_already_defined_in_scope};
        false ->
            {ok, S#scope{funs = dict:store(Name, F, FunDict)}}
    end.


%% @private
internal_get_fun(S=#scope{}, FunName) ->
    util:ensure_string_type(FunName),
    case dict:find(FunName, S#scope.funs) of
        {ok, Fun} ->
            {ok, Fun};
        error ->
            {err, not_in_scope}
    end.


%% @private
internal_add_var(#scope{framesStack = []}, _VarAddr, _VarType, _VarProperties) ->
    % there is no open frame
    {err, no_open_scopes};
internal_add_var(S, VarAddr, VarType, VarProperties) when is_record(S, scope) ->
    util:ensure_properties_are_valid(VarProperties),
    util:ensure_type_is_canonical(VarType),
    [VarDict | NestedFrames] = S#scope.framesStack,
    case dict:is_key(VarAddr, VarDict) of
        true ->
            {err, var_already_defined_in_scope};
        false ->
            Var = util:make_variable(VarAddr, VarType, VarProperties),
            VarDict_1 = dict:store(VarAddr, Var, VarDict),
            Scope_1 = S#scope{framesStack = [VarDict_1 | NestedFrames]},
            {ok, Scope_1}
    end.


%% @private
internal_read_var(S=#scope{}, VarName) ->
%%     util:ensure_string_type(VarName),
    case internal_find_var(VarName, S#scope.framesStack) of
        {ok, #variable{isGlobal = true}} ->
            {ok, global_var};
        {ok, #variable{type = Type, value = Value}} ->
            {ok, Type, Value};
        not_in_scope ->
            logger:log("internal read var: ~p~n     => not in scope   vars: ~p",
                ?MODULE, [VarName, [dict:to_list(V) || V <- S#scope.framesStack]]),
            {err, not_in_scope}
    end.


%% @private
internal_write_var(_VarName, _NewValue, []) ->
    % var not found in any scope
    {err, not_in_scope};
internal_write_var(VarName, NewValue, [VDict | NestedFrames]) ->
    case dict:find(VarName, VDict) of
        {ok, #variable{isGlobal = true}} ->
            % if var is global signal an error
            {err, global_var};
        {ok, #variable{isConst = true, value = Val}} when Val =/= undefined ->
            % if var is const and already set signal an error
            {err, const_var};
        {ok, Var} ->
            % if var found then update the frame and return the updated stack
            % (or it's the first assignment of a const var when it has no value set yet)
            % TODO: verify that the new value's type matches the current type of the variable
            Var_1 = Var#variable{value = NewValue},
            VDict_1 = dict:store(VarName, Var_1, VDict),
            FramesStack_1 = [VDict_1 | NestedFrames],
            {ok, FramesStack_1};
        error ->
            % error == no such var in current frame; try recursively in nested frames
            case internal_write_var(VarName, NewValue, NestedFrames) of
                {err, Reason} ->
                    % if failed then forward the error
                    {err, Reason};
                {ok, NestedFrames_1} ->
                    % else return an updated stack of frames
                    FramesStack_1 = [VDict | NestedFrames_1],
                    {ok, FramesStack_1}
            end
    end.


%% @private
-spec internal_find_var(VarName, StackOfFrames) -> Result when
    VarName       :: string_type(),
    StackOfFrames :: [],
    Result        :: not_in_scope | global_var | {ok, #variable{}}.
internal_find_var(_VarName, []) ->
    not_in_scope;
internal_find_var(VarName, [VDict | NestedFrames]) ->
    % look in the top-most open frame
    case dict:find(VarName, VDict) of
        {ok, Var} ->
            % if found the var then return it in the same way
            {ok, Var};
        error ->
            % else try recursively in outer scopes
            internal_find_var(VarName, NestedFrames)
    end.


