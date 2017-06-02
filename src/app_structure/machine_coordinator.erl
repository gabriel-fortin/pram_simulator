%%%-------------------------------------------------------------------
%%% @author Gabriel Fortin
%%% @copyright (C) 2016, Gabriel Fortin
%%% @doc
%%% Prepares a program so the {@link manager} can execute it.
%%%
%%% Reads a program's file and parses it to AST form. Validates the AST.
%%%  Prepares input and output files. Starts the manager and controls
%%%  its actions thus interfacing between the manager and a user.
%%%
%%% @end
%%% Created : 27. Feb 2016 10:52 AM
%%%-------------------------------------------------------------------
-module(machine_coordinator).
-author("Gabriel Fortin").

-behaviour(gen_server).


-include("../common/defs.hrl").

%% API
-export([
    start_link/2,
    set_input_file/2,
    set_output_file/2,
    set_program_file/2,
    set_memory_model/2,
    parse_program/1,
    execute_program/1,
    get_stats/1,
    write_output/1
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).


-record(mcState, {
    input_io_server     = undefined     :: pid(),
    output_io_server    = undefined     :: pid(),
    program_text        = undefined,
    program_ast         = undefined,
    manager             = undefined     :: pid(),
    memory_model        = 'EREW',
    supervisor
}).



%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec start_link(_MachineName, MachineSupervisor :: pid()) ->
    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}.
start_link(MachineName, MachineSupervisor) ->
    % starting a named server - the main process for a program's execution
    Args = [MachineSupervisor],
    gen_server:start_link({local, MachineName}, ?MODULE, Args, _Opts=[]).


set_input_file(NameOrPid, InputFileName) ->
    case gen_server:call(NameOrPid, {set_input_file, InputFileName}) of
        ok ->
            ok;
        {err, SomeError} ->
            throw({input_file_failure, {got, InputFileName}, SomeError})
    end.


set_output_file(NameOrPid, OutputFileName) ->
    case gen_server:call(NameOrPid, {set_output_file, OutputFileName}) of
        ok ->
            ok;
        {err, SomeError} ->
            throw({output_file_failure, {got, OutputFileName}, SomeError})
    end.


set_program_file(NameOrPid, ProgramFileName) ->
    case gen_server:call(NameOrPid, {set_program_file, ProgramFileName}) of
        ok ->
            ok;
        {err, SomeError} ->
            throw({program_name_failure, {got, ProgramFileName}, SomeError})
    end.


parse_program(NameOrPid) ->
    case gen_server:call(NameOrPid, parse_program) of
        ok ->
            ok;
        {err, SomeError} ->
            throw({parsing_failure, SomeError})
    end.


execute_program(NameOrPid) ->
    case gen_server:call(NameOrPid, run_program) of
        ok ->
            ok;
        {err, SomeError} ->
            throw({execution_failure, SomeError})
    end.


set_memory_model(NameOrPid, MemoryModel) ->
    case gen_server:call(NameOrPid, {set_memory_model, MemoryModel}) of
        ok ->
            ok;
        {err, SomeError} ->
            throw({memory_model_failure, {got, MemoryModel}, SomeError})
    end.


get_stats(NameOrPid) ->
    case gen_server:call(NameOrPid, get_stats) of
        {ok, Stats} ->
            {ok, Stats};
        {err, SomeError} ->
            {err, SomeError}
    end.


write_output(NameOrPid) ->
    case gen_server:call(NameOrPid, write_output) of
        ok ->
            ok;
        {err, SomeError} ->
            throw({output_writing_failure, SomeError})
    end.



%%%===================================================================
%%% functionality's core
%%%===================================================================

internal_set_input_file(#mcState{manager = Manager}, _InputFileName)
    when Manager =/= undefined ->
    throw({err, program_already_started});

internal_set_input_file(State, InputFileName) ->
    case start_input_server(State, InputFileName) of
        {ok, InputServerPid} ->
            State_1 = State#mcState{input_io_server = InputServerPid},
            {ok, State_1};
        {error, Reason} ->
            throw({err, Reason})
    end.


internal_set_output_file(State, OutputFileName) ->
    case start_output_server(State, OutputFileName) of
        {ok, OutputServerPid} ->
            State_1 = State#mcState{output_io_server = OutputServerPid},
            {ok, State_1};
        {error, Reason} ->
            throw({err, Reason})
    end.


internal_set_program_file(#mcState{manager = Manager}, _ProgramFileName)
    when Manager =/= undefined ->
    throw({err, program_already_started});

internal_set_program_file(State, ProgramFileName) ->
    {ok, BinaryContent} = read_program_file(ProgramFileName),
    {ok, ProgramText} = translate_to_unicode(BinaryContent),

    State_1 = State#mcState{program_text = ProgramText},
    {ok, State_1}.


internal_parse_program(#mcState{manager = Manager})
    when Manager =/= undefined ->
    throw({err, program_already_started});

internal_parse_program(#mcState{program_text = ProgramText})
    when ProgramText == undefined ->
    throw({err, no_program_set});

internal_parse_program(State) ->
    ProgramText = State#mcState.program_text,

    {ok, Tokens, EndLine} = scan_for_tokens(ProgramText),
    {ok, ProgramAst} = parse_to_ast(Tokens, EndLine),
    {ok, ValidatedAst} = validate(ProgramAst),

    State_1 = State#mcState{program_ast = ValidatedAst},
    {ok, State_1}.


internal_run_program(#mcState{manager = Manager})
    when Manager =/= undefined ->
    throw({err, program_already_started});

internal_run_program(#mcState{input_io_server = Input})
    when Input == undefined ->
    throw({err, no_input_set});

internal_run_program(#mcState{program_ast = Program})
    when Program == undefined ->
    throw({err, no_parsed_program});

internal_run_program(State) ->
    % TODO: handle errors occurring in execution? or just let it all crash?
    Manager = start_manager(State),
    ProgramAst = State#mcState.program_ast,
    InputServer = State#mcState.input_io_server,
    MemoryModel = State#mcState.memory_model,

    ok = manager:prepare(Manager, ProgramAst, InputServer, MemoryModel),
    ok = manager:launch(Manager, execution_termination_callback()),
%%    erlang:send_after() %TODO 'send_after' instead of what is below
    wait_for_execution_termination_callback(),

    State_1 = State#mcState{manager = Manager},
    {ok, State_1}.


internal_set_memory_model(#mcState{manager = Manager}, _Model)
    when Manager =/= undefined ->
    throw({err, program_already_started});

internal_set_memory_model(State, Model) ->
    State_1 = State#mcState{memory_model = Model},
    {ok, State_1}.


internal_get_stats(#mcState{manager = Manager})
    when not is_pid(Manager) ->
    throw({err, program_not_executed});

internal_get_stats(State) ->
    Manager = State#mcState.manager,
    {ok, Stats} = manager:get_stats(Manager),
    {{ok, Stats}, State}.


internal_write_output(#mcState{output_io_server = Output})
    when Output == undefined ->
    throw({err, no_output_set});

internal_write_output(#mcState{manager = Manager})
    when not is_pid(Manager) ->
    throw({err, program_not_executed});

internal_write_output(State) ->
    Manager = State#mcState.manager,
    OutputServer = State#mcState.output_io_server,
    Result = manager:write_output(Manager, OutputServer),
    {Result, State}.



%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
    {ok, State :: #mcState{}} | {ok, State :: #mcState{}, timeout() | hibernate} |
    {stop, Reason :: term()} | ignore).
init([MachineSupervisor]) ->
    State = #mcState{
        supervisor = MachineSupervisor
    },
    {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #mcState{}) ->
    {reply, Reply :: term(), NewState :: #mcState{}} |
    {reply, Reply :: term(), NewState :: #mcState{}, timeout() | hibernate} |
    {noreply, NewState :: #mcState{}} |
    {noreply, NewState :: #mcState{}, timeout() | hibernate} |
    {stop, Reason :: term(), Reply :: term(), NewState :: #mcState{}} |
    {stop, Reason :: term(), NewState :: #mcState{}}).
handle_call(CallArg, _From, State) ->
    try
        {Response, State_1} =
            case CallArg of
                {set_input_file, InputFileName} ->
                    internal_set_input_file(State, InputFileName);
                {set_output_file, OutputFileName} ->
                    internal_set_output_file(State, OutputFileName);
                {set_program_file, ProgramFileName} ->
                    internal_set_program_file(State, ProgramFileName);
                {set_memory_model, Model} ->
                    internal_set_memory_model(State, Model);
                parse_program ->
                    internal_parse_program(State);
                run_program ->
                    internal_run_program(State);
                get_stats ->
                    internal_get_stats(State);
                write_output ->
                    internal_write_output(State);
                Other ->
                    throw({unrecognized_message, {got, Other}})
            end,
        {reply, Response, State_1}
    catch
        throw:{err, Reason} ->
            {reply, {err, Reason}, State}
    end.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #mcState{}) ->
    {noreply, NewState :: #mcState{}} |
    {noreply, NewState :: #mcState{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #mcState{}}).
handle_cast(_Request, State) ->
    {noreply, State}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #mcState{}) ->
    {noreply, NewState :: #mcState{}} |
    {noreply, NewState :: #mcState{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #mcState{}}).
handle_info(_Info, State) ->
    {noreply, State}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #mcState{}) -> term()).
terminate(_Reason, _State) ->
    % when io_servers are attached to a supervisor's tree they auto-close on shutdown
    % other elements of state don't need any special action
    ok.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #mcState{},
    Extra :: term()) ->
    {ok, NewState :: #mcState{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.



%%%===================================================================
%%% Internal functions
%%%===================================================================

read_program_file(ProgramFileName) ->
    case file:read_file(ProgramFileName) of
        {ok, BinaryContent} ->
            {ok, BinaryContent};
        {error, Reason} ->
            throw({err, Reason})
    end.


translate_to_unicode(Binary) ->
    case unicode:characters_to_list(Binary) of
        List when is_list(List) ->
            {ok, List};
        DecErr = {error, _, _} ->
            throw({err, DecErr});
        IncErr = {incomplete, _, _} ->
            throw({err, IncErr})
    end.


scan_for_tokens(ProgramText) ->
    case scanner:string(ProgramText) of
        {ok, Tokens, EndLine} ->
            {ok, Tokens, EndLine};
        E = {ErrorLine, _, ErrorDesc} ->
            io:format("~nfailed to tokenize program ~nline: ~p~nproblem: ~p~n~n",
                [ErrorLine, ErrorDesc]),
            throw({err, E})
    end.


parse_to_ast(Tokens, EndLine) ->
    ParserInput = Tokens ++ [{code_end_marker, EndLine}],
    case parser:parse(ParserInput) of
        {ok, Ast} ->
            {ok, Ast};
        Err = {error, {LineNumber, _Module, Message}} ->
            io:format("~nfailed to parse program ~nline: ~p~nproblem: ~p~n~n",
                [LineNumber, Message]),
            throw({err, Err})
    end.


validate(ProgramAst) ->
    case validation:program_ast(ProgramAst) of
        ok ->
            {ok, ProgramAst};
        Err = {validation_failure, Failure} ->
            io:format("~nfailed to validate program ~ncause:~n~p~n~n", [Failure]),
            throw({err, Err})
    end.


execution_termination_callback() ->
    Self = self(),
    fun() ->
        Self ! execution_ended
    end.


wait_for_execution_termination_callback() ->
    Timeout = 7500,
    receive
        execution_ended ->
            logger:log("program ended", ?MODULE),
            ok
    after Timeout ->
        io:format("waiting for execution termination (~p)~n", [?MODULE]),
        wait_for_execution_termination_callback()
    end.


start_manager(State) ->
    MachineSupervisor = State#mcState.supervisor,
    Args = [{supervisor, MachineSupervisor}],
    ManagerChildSpec = {
        manager,
        {manager, start_link, Args},
        ?MANAGER_RESTART_STRATEGY,
        ?MANAGER_SHUTDOWN_TIMEOUT,
        worker,
        [manager, ?MANAGER_IMPL_MODULE]
    },
    {ok, Manager} = supervisor:start_child(MachineSupervisor, ManagerChildSpec),
    Manager.


% a supervisor's child specification template for an 'io_server' process
-define(IO_SERVER_CHILD_SPEC(Function, Args), {
    {io_server, Function, Args},  % name used by supervisor
    {io_server, Function, Args},  % start function and args
    ?WORKER_RESTART_STRATEGY,
    ?WORKER_SHUTDOWN_TIMEOUT,
    worker,  % child type
    [io_server]  % impl module
}).


start_input_server(State, InputFileName) ->
    MachineSupervisor = State#mcState.supervisor,
    InputServerChildSpec = ?IO_SERVER_CHILD_SPEC(read_from_file, [InputFileName]),
    supervisor:start_child(MachineSupervisor, InputServerChildSpec).


start_output_server(State, OutputFileName) ->
    MachineSupervisor = State#mcState.supervisor,
    OutputServerChildSpec = ?IO_SERVER_CHILD_SPEC(write_to_file, [OutputFileName]),
    supervisor:start_child(MachineSupervisor, OutputServerChildSpec).

