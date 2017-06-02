%%%-------------------------------------------------------------------
%%% @author Gabriel Fortin
%%% @copyright (C) 2015, Gabriel Fortin
%%% @doc
%%%
%%% @end
%%% Created : 02. Sep 2015 8:29 PM
%%%-------------------------------------------------------------------
-module(mem_impl).
-author("Gabriel Fortin").

-behaviour(gen_server).



-include("../common/ast.hrl").
-include("../common/defs.hrl").


%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).


-record(mem_state, {
    vars                = dict:new(),
    access_register     = [],
    access_type         = no_access_yet,    %% helps to ensure that reads are not mixed with writes
    access_model        = none,
    access_violations   = []
}).


% NB: this is only a subset of "recognised memory models" (as defined in the 'mem' module)
%   - the 'CRCW priority' model was not implemented
-define(ALLOWED_MEMORY_MODELS, [none, 'EREW', 'CREW', 'CRCW common', 'CRCW arbitrary']).

-define(exclusive_read(Model), (Model == 'EREW')).
-define(exclusive_write(Model), ((Model == 'EREW') or (Model == 'CREW'))).
-define(common_write(Model), (Model == 'CRCW common')).
-define(arbitrary_write(Model), (Model == 'CRCW arbitrary')).



% used by init/1
-spec initialize(MemModel) -> {ok, State}
    when    MemModel    :: tMemModel(),
            State       :: #mem_state{}.
initialize(MemModel)
    ->
    case lists:member(MemModel, ?ALLOWED_MEMORY_MODELS) of
        false ->
            {stop, report_model_not_supported(MemModel)};
        true ->
            State = #mem_state{
                access_model = MemModel},
            {ok, State}
    end.


set_memory_model(State, Model) ->
    case lists:member(Model, ?ALLOWED_MEMORY_MODELS) of
        false ->
            logger:log("ERROR: setting a model that is not supported", ?MODULE),
            Result = {err, report_model_not_supported(Model)},
            {Result, State};
        true ->
            State_1 = State#mem_state{
                access_model = Model},
            {ok, State_1}
    end.


deliver_clock_event(State)
    when State#mem_state.access_model == none ->
    {ok, reset_access_trace(State)};

deliver_clock_event(State) ->
    Model = State#mem_state.access_model,
    Violations = State#mem_state.access_violations,
    Action = State#mem_state.access_type,

    case Violations of
        [] ->
            Result = ok;
        [_|_] ->
            logger:log("tick, VIOLATIONS: ~p", ?MODULE, [Violations]),
            Result = {err, memory_model_violation, {model, Model}, {action, Action}, Violations}
    end,

    {Result, reset_access_trace(State)}.


-spec add_var(State, VarType, _VarName, VarProperties) -> ok | {error, var_already_defined}
    when    State           :: #mem_state{},
            VarType         :: tVarType(),
            VarProperties   :: [varProperty()].
add_var(State, VarType, VarName, VarProperties)
    when is_record(State, mem_state)
    ->
    util:ensure_type_is_canonical(VarType),
    util:ensure_properties_are_valid(VarProperties),
    case dict:is_key(VarName, State#mem_state.vars) of
        true ->
            {{err, var_already_defined}, State};
        false ->
            State_1 = add_var_to_state(VarName, VarType, VarProperties, State),
            {ok, State_1}
    end.


-spec read_var(State, _VarName) -> {{ok, TypeAndVal} | {err, Err}, State}
    when    State       :: #mem_state{},
            TypeAndVal  :: {tVarType(), any()},
            Err         :: no_such_global_var | not_initialised | invalid_memory_access.
read_var(State, _VarName)
    when State#mem_state.access_type == write
    ->
    logger:log("access type was ~p   but trying to read -->ERR", ?MODULE,
            [State#mem_state.access_type]),
    {{err, invalid_memory_access}, State};

read_var(State, VarName)
    when State#mem_state.access_model == none
    ->
    Result = memory_read(State, VarName),
    {Result, State};

read_var(State, VarName)
    ->
    Model = State#mem_state.access_model,
    Register = State#mem_state.access_register,
    Violations = State#mem_state.access_violations,
    WasAlreadyRead = lists:member(VarName, Register),

    % model validation
    if
        WasAlreadyRead and ?exclusive_read(Model) ->
            NewViolations = [VarName | Violations];
        true ->
            NewViolations = Violations
    end,
    if
        WasAlreadyRead ->
            NewRegister = Register;
        not WasAlreadyRead ->
            NewRegister = [VarName | Register]
    end,

    State_1 = State#mem_state{
        access_register = NewRegister,
        access_type = read,
        access_violations = NewViolations},

    Result = memory_read(State, VarName),

    {Result, State_1}.


-spec write_var(State, _VarName, _Value) -> {ok | {err, Err}, State}
    when    State       :: #mem_state{},
            Err         :: no_such_global_var | invalid_memory_access.
write_var(State, _VarName, _Value)
    when State#mem_state.access_type == read
    ->
    logger:log("access type was ~p   but trying to WRITE -->ERR", ?MODULE,
            [State#mem_state.access_type]),
    {_Result={err, invalid_memory_access}, State};

write_var(State, VarName, Value)
    when State#mem_state.access_model == none
    ->
    {_Result, _State} = memory_write(State, VarName, Value);

write_var(State, VarName, Value)
    ->
    Model = State#mem_state.access_model,
    Register = State#mem_state.access_register,
    Violations = State#mem_state.access_violations,
    case dict:find(VarName, State#mem_state.vars) of
        error ->
            {{err, no_such_global_var}, State};
        {ok, VarEntry} ->
            CurrentValue = VarEntry#variable.value,
            WasAlreadyWritten = lists:member(VarName, Register),

            % model validation
            if
                WasAlreadyWritten and ?exclusive_write(Model) ->
                    V = {VarName, exclusive_write},
                    NewViolations = [V | Violations];
                WasAlreadyWritten and ?common_write(Model) and (CurrentValue =/= Value) ->
                    V = {VarName, common_write, {old, CurrentValue}, {new, Value}},
                    NewViolations = [V | Violations];
                WasAlreadyWritten and ?arbitrary_write(Model) ->
                    NewViolations = Violations;
                WasAlreadyWritten ->
                    NewViolations = Violations;
                not WasAlreadyWritten ->
                    NewViolations = Violations
            end,
            if
                WasAlreadyWritten ->
                    NewRegister = Register;
                not WasAlreadyWritten ->
                    NewRegister = [VarName | Register]
            end,

            {Result, State_1} = memory_write(State, VarName, Value),

            State_2 = State_1#mem_state{
                access_register = NewRegister,
                access_type = write,
                access_violations = NewViolations},

            {Result, State_2}
    end.


-spec get_all_vars(State) -> [{VarType, _VarName}]
    when    State       :: #mem_state{},
            VarType     :: tVarType().
get_all_vars(State)
    ->
    KeyValues = dict:to_list(State#mem_state.vars),
    Result = lists:map(
        fun({VarName, #variable{type = VarType}}) ->
            {VarType, VarName}
        end,
        KeyValues),
    {{ok, Result}, State}.


-spec get_all_variables(State) -> [Variable]
    when    State       :: #mem_state{},
            Variable    :: #variable{}.
get_all_variables(State)
    when is_record(State, mem_state)
    ->
    KeyValues = dict:to_list(State#mem_state.vars),
    Result = lists:map(
        fun({_VarName, Variable}) ->
            Variable
        end,
        KeyValues),
    {{ok, Result}, State}.



%%%===================================================================
%%% Internal functions
%%%===================================================================

add_var_to_state(VarName, VarType, VarProperties, State)
    ->
    Entry = util:make_variable(VarName, VarType, VarProperties),
    Vars_1 = dict:store(VarName, Entry, State#mem_state.vars),
    State#mem_state{vars = Vars_1}.


memory_read(State, VarName) ->
    case dict:find(VarName, State#mem_state.vars) of
        error ->
            {err, no_such_global_var};
        {ok, #variable{value = undefined}} ->
            {err, not_initialised};
        {ok, #variable{type = VarType, value = Value}} ->
            {ok, {VarType, Value}}
    end.


memory_write(State, VarName, Value) ->
    Vars = State#mem_state.vars,
    case dict:find(VarName, Vars) of
        error ->
            {{err, no_such_global_var}, State};
        {ok, Entry} ->
            State_1 = update_state_with_value(Entry, Value, VarName, State),
            {ok, State_1}
    end.


update_state_with_value(Entry, Value, VarName, State)
    ->
    Entry_1 = Entry#variable{value = Value},
    Vars_1 = dict:store(VarName, Entry_1, State#mem_state.vars),
    _NewState = State#mem_state{vars = Vars_1}.


reset_access_trace(State) ->
    State#mem_state{
        access_register = [],
        access_type = no_access_yet,
        access_violations = []
    }.


report_model_not_supported(Model) ->
    {this_memory_model_is_currently_not_supported, {model, Model},
        {allowed_models, ?ALLOWED_MEMORY_MODELS}}.



%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @private
-spec(init(MemModel :: tMemModel()) ->
    {ok, State :: #mem_state{}} | {ok, State :: #mem_state{}, timeout() | hibernate} |
    {stop, Reason :: term()} | ignore).
init(MemModel) ->
    initialize(MemModel).


%% @private
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #mem_state{}) ->
    {reply, Reply :: term(), NewState :: #mem_state{}} |
    {reply, Reply :: term(), NewState :: #mem_state{}, timeout() | hibernate} |
    {noreply, NewState :: #mem_state{}} |
    {noreply, NewState :: #mem_state{}, timeout() | hibernate} |
    {stop, Reason :: term(), Reply :: term(), NewState :: #mem_state{}} |
    {stop, Reason :: term(), NewState :: #mem_state{}}).
handle_call(tick, _From, State) ->
    {Result, NewState} = deliver_clock_event(State),
    {reply, Result, NewState};
handle_call({set_model, Model}, _From, State) ->
    {Result, NewState} = set_memory_model(State, Model),
    {reply, Result, NewState};
handle_call({add_var, VarType, VarName, VarProperties}, _From, State) ->
    {Result, NewState} = add_var(State, VarType, VarName, VarProperties),
    {reply, Result, NewState};
handle_call({read_var, VarName}, _From, State) ->
    {Result, NewState} = read_var(State, VarName),
    {reply, Result, NewState};
handle_call({write_var, VarName, Value}, _From, State) ->
    {Result, NewState} = write_var(State, VarName, Value),
    {reply, Result, NewState};
handle_call(get_all_vars, _From, State) ->
    {Result, NewState} = get_all_vars(State),
    {reply, Result, NewState};
handle_call(get_all_variables, _From, State) ->
    {Result, NewState} = get_all_variables(State),
    {reply, Result, NewState};
handle_call(AnythingElse, _From, State) ->
    io:format("ERROR: ~p: received an unrecognized gen_server callback~n"
            ++"       request: ~p~n", [?MODULE, AnythingElse]),
    {noreply, State}.


%% @private
-spec(handle_cast(Request :: term(), State :: #mem_state{}) ->
    {noreply, NewState :: #mem_state{}} |
    {noreply, NewState :: #mem_state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #mem_state{}}).
handle_cast(Request, State) ->
    io:format("ERROR: ~p: unsupported: received a cast in a gen_server callback~n"
            ++"       cast request content: ~p~n", [?MODULE, Request]),
    {noreply, State}.


%% @private
-spec(handle_info(Info :: timeout() | term(), State :: #mem_state{}) ->
    {noreply, NewState :: #mem_state{}} |
    {noreply, NewState :: #mem_state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #mem_state{}}).
handle_info(Info, State) ->
    io:format("ERROR: ~p: unsupported: received an info in a gen_server callback~n"
            ++"       info content: ~p~n", [?MODULE, Info]),
    {noreply, State}.


%% @private
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #mem_state{}) -> term()).
terminate(Reason, _State) ->
    logger:log("info: terminating, reason: ~p", ?MODULE, [Reason]),
    ok.


%% @private
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #mem_state{},
    Extra :: term()) ->
    {ok, NewState :: #mem_state{}} | {error, Reason :: term()}).
code_change(_OldVsn, _State, _Extra) ->
    {error, not_supported}.
