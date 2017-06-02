%%%-------------------------------------------------------------------
%%% @author Gabriel Fortin
%%% @copyright (C) 2015, Gabriel Fortin
%%% @doc
%%%
%%% @end
%%% Created : 24. May 2015 11:23 AM
%%%-------------------------------------------------------------------
-module(scope).
-author("Gabriel Fortin").

%% Remarks
%%  — scope doesn't support arrays - they are supposed to be global vars



-include("../common/ast.hrl").
-include("../common/defs.hrl").


%% API
-export([
    start_link/0,
    start_link/1,
    open_frame/1,
    close_frame/1,
    add_fun/2,
    get_fun/2,
    add_var/4,
    read_var/2,
    read_var_and_type/2,
    write_var/3
]).

%% temporary exports for tests!
-export([new_var/3]).  %% TODO: delete



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%  API FUNCTIONS' DEFINITIONS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%--------------------------------------------------------------------
%% @doc
%% Creates a new scope process.
%%
%% @end
%%--------------------------------------------------------------------
-spec start_link() -> {ok, Scope} | ignore | {error, Error}
        when    Scope   :: pid(),
                Error   :: {already_started, pid()} | term().
start_link() ->
    Module = ?SCOPE_IMPL_MODULE,
    {ok, _ScopePid} = gen_server:start_link(Module, _Arg=[], _Opts=[]).


%%--------------------------------------------------------------------
%% @doc
%% Creates a scope process that is a copy of the given scope.
%%
%% @end
%%--------------------------------------------------------------------
-spec start_link(ScopeToCopy) -> {ok, Scope} | ignore | {error, Error}
        when    ScopeToCopy     :: pid(),
                Scope           :: pid(),
                Error           :: {already_started, pid()} | term().
start_link(ScopeToCopy)
        when is_pid(ScopeToCopy) ->
    Module = ?SCOPE_IMPL_MODULE,
    Arg = {scope_to_copy, ScopeToCopy},
    {ok, _NewScopePid} = gen_server:start_link(Module, Arg, _Opts=[]).


%%--------------------------------------------------------------------
%% @doc
%% Creates a new frame in the scope.
%%
%% Each nested block of code defines a nested scope and therefore
%% should be accompanied by a scope frame. Such a frame should stay
%% opened as long as the (related) code block is not left.
%% <br />
%% Opening a frame should be followed by a corresponding call to
%% {@link close_frame/1}.
%%
%% @end
%%--------------------------------------------------------------------
-spec open_frame(Scope) -> ok
        when    Scope    :: pid().
open_frame(ScopePid)
        when is_pid(ScopePid) ->
    gen_server:call(ScopePid, open_frame).


%%--------------------------------------------------------------------
%% @doc
%% Deletes the top frame of the scope.
%%
%% @throws no_open_scopes
%% @end
%%--------------------------------------------------------------------
-spec close_frame(Scope) -> ok
        when    Scope    :: pid().
close_frame(ScopePid)
        when is_pid(ScopePid) ->
    case gen_server:call(ScopePid, close_frame) of
        {err, no_open_scopes} ->
            throw(no_open_scopes);
        ok ->
            ok
    end.


%%--------------------------------------------------------------------
%% @doc
%% Adds a function definition to the scope.
%%
%% @throws {fun_already_defined_in_scope, FunName::string_type()}
%% @end
%%--------------------------------------------------------------------
-spec add_fun(Scope, Function) -> ok
        when    Scope       :: pid(),
                Function    :: #rFunctionDef{}.
add_fun(ScopePid, Function)
        when is_pid(ScopePid),
            is_record(Function, rFunctionDef) ->
    case gen_server:call(ScopePid, {add_fun, Function}) of
        {err, fun_already_defined_in_scope} ->
            throw({fun_already_defined_in_scope, Function#rFunctionDef.ident});
        ok ->
            ok
    end.


%%--------------------------------------------------------------------
%% @doc
%% Gets a function definition from the scope
%%
%% @throws {not_in_scope, FunName::string_type()}
%% @end
%%--------------------------------------------------------------------
-spec get_fun(Scope, FunName) -> {ok, Function}
        when    Scope       :: pid(),
                FunName     :: string_type(),
                Function    :: #rFunctionDef{}.
get_fun(ScopePid, FunName)
        when is_pid(ScopePid) ->
    util:ensure_string_type(FunName),
    case gen_server:call(ScopePid, {get_fun, FunName}) of
        {err, not_in_scope} ->
            throw({not_in_scope, FunName});
        {ok, Fun} ->
            {ok, Fun}
    end.


%%--------------------------------------------------------------------
%% @doc
%% Adds a var to the scope's current frame.
%%
%% Valid values for the properties' list: <code>global</code>,
%% <code>const</code>, <code>input_var</code>,
%% <code>output_var</code>.
%%
%% @throws no_open_scopes | {var_already_defined_in_scope, VarAddr}
%% @end
%%--------------------------------------------------------------------
-spec add_var(Scope, VarAddr, VarType, VarProperties) -> ok
        when    Scope           :: pid(),
                VarAddr         :: tVarAddr(),
                VarType         :: global_var | tVarType(),
                VarProperties   :: [varProperty()].
add_var(ScopePid, VarAddr, VarType, VarProperties)
        when is_pid(ScopePid),
            is_list(VarProperties) ->
    logger:log("~p add var (API): ~p ~p", ?MODULE, [self(), VarAddr, VarProperties]),
    logger:log("   of type  ~100p", ?MODULE, [VarType]),
    case VarType of
        #rSimpleVarType{} -> ok;
        #rArrayVarType{} -> ok;
        _ -> throw({expected, {rSimpleVarType, rArrayVarType}, got, VarType})
    end,
    case gen_server:call(ScopePid, {add_var, VarAddr, VarType, VarProperties}) of
        {err, no_open_scopes} ->
            throw(no_open_scopes);
        {err, var_already_defined_in_scope} ->
            throw({var_already_defined_in_scope, VarAddr});
        ok ->
            ok
    end.


%%--------------------------------------------------------------------
%% @doc
%% Reads a var value from the scope.
%%
%% @throws {not_in_scope, VarName::string_type()}
%% @end
%%--------------------------------------------------------------------
-spec read_var(Scope, VarAddr) -> Result
        when    Scope       :: pid(),
                VarAddr     :: tVarAddr(),
                Result      :: {ok, _VarValue} | {err, global_var}.
read_var(ScopePid, VarAddr)
        when is_pid(ScopePid),
            is_record(VarAddr, var_addr) ->
    case gen_server:call(ScopePid, {read_var, VarAddr}) of
        {err, not_in_scope} ->
            throw({not_in_scope, VarAddr});
        {ok, global_var} ->
            {err, global_var};
        {ok, VarValue, _VarType} ->
            {ok, VarValue}
    end.


%%--------------------------------------------------------------------
%% @doc
%% Reads a var value and type from the scope.
%%
%% @throws {not_in_scope, VarName::string_type()}
%% @end
%%--------------------------------------------------------------------
-spec read_var_and_type(Scope, VarAddr) -> Result
        when    Scope       :: pid(),
                VarAddr     :: tVarAddr(),
                Result      :: {ok, _VarValue, _VarType} | {err, global_var}.
read_var_and_type(ScopePid, VarAddr)
        when is_pid(ScopePid),
            is_record(VarAddr, var_addr) ->
    logger:log("~p read var and type for ~p", ?MODULE, [self(), VarAddr]),
    case gen_server:call(ScopePid, {read_var, VarAddr}) of
        {err, not_in_scope} ->
            throw({not_in_scope, VarAddr});
        {ok, global_var} ->
            {err, global_var};
        {ok, VarValue, VarType} ->
            {ok, VarValue, VarType}
    end.


%%--------------------------------------------------------------------
%% @doc
%% Writes a value to a var in the scope.
%%
%% @throws {not_in_scope|global_var, VarName::string_type()}
%% @end
%%--------------------------------------------------------------------
-spec write_var(Scope, VarAddr, VarValue) -> ok
        when    Scope    :: pid(),
                VarAddr  :: tVarAddr(),
                VarValue :: any().  %% varValue().
write_var(ScopePid, VarAddr, VarValue)
        when is_pid(ScopePid),
            is_record(VarAddr, var_addr) ->
    case VarValue of
        #rConstVal{} ->
            throw({expected, "raw value", got, VarValue});
        _ ->
            ok
    end,
    case gen_server:call(ScopePid, {write_var, VarAddr, VarValue}) of
        {err, not_in_scope} ->
            throw({not_in_scope, VarAddr});
        {err, global_var} ->
            throw({global_var, VarAddr});
        {err, const_var} ->
            throw({const_var, VarAddr});
        ok ->
            ok
    end.



% ONLY FOR TESTS!   TODO: delete
%% @hidden
new_var(Name, int, Value) ->   %% TODO: delete
%%     #var{
%%         name = Name,
%%         type = #rSimpleVarType{typeName = 'int'},
%%         value = Value }.
    {var, Name, #rSimpleVarType{typeName = 'int'}, Value}.
