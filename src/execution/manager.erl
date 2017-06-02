%%%-------------------------------------------------------------------
%%% @author Gabriel Fortin
%%% @copyright (C) 2015, Gabriel Fortin
%%% @doc
%%%
%%% @end
%%% Created : 03. Jun 2015 9:08 PM
%%%-------------------------------------------------------------------
-module(manager).
-author("Gabriel Fortin").

-behaviour(gen_fsm).


% The manager loop will wait until all its subscribers (e.g. processors) send
%  a request and then will reply (possibly only to a part of them) that
%  the requested event happened (possibly sending also some info about
%  that event).
% The 'sync_on_tick' function is called for any action (in the execution of
%  a program) that is considered to be atomic and accountable. Therefore, it
%  serves the needs of instruction counting.
% The purpose of 'request_barrier' and 'sync_on_barrier' functions is to mimic
%  the behaviour of a PRAM where all processors share the same instruction
%  pointer. For example, when one processor goes inside an "if" statement then
%  other processors must wait for that one processor to exit the "if"-block.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%  includes and exports
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-include("../common/ast.hrl").
-include("../common/defs.hrl").


%% API -- to be called by a user of this module
-export([
    start_link/1,       % starts a new manager with a clean state
    prepare/4,          % performs the pre-execution phase (loads data)
    launch/2,           % starts the proper-execution phase
    get_stats/1,        % returns stats of the proper-execution phase
    write_output/2      % write output to the given io_server
]).


%% API -- to be called by a "subscriber" (e.g. a processor)
-export([
    sync_on_tick/1,         % wait for other processors to finish their computation's cycle
    request_barrier/1,      % get a barrier (to synchronize on it in a later time)
    sync_on_barrier/2,      % wait for other processors synchronizing on the same barrier
    register_processor/2,   % include the processor in the synchronization and stats mechanisms
    unregister_processor/2, % undo the registration performed with register_processor/2
    suspend_registration/2, % begin a temporary exclusion from stats
    resume_registration/2   % end a temporary exclusion from stats
]).


%% gen_fsm behaviour's callbacks
-export([
    is_new/3,       % gen_fsm state
    is_ready/3,     % gen_fsm state
    is_working/3,   % gen_fsm state
    is_finished/3,  % gen_fsm state
    is_finished/2,  % gen_fsm state
    init/1,                 % initializes a just-starting manager
    terminate/3,            % performs clean-up of a dying manager
    handle_event/3,         % required by the gen_fsm behaviour, unused
    handle_sync_event/4,    % required by the gen_fsm behaviour, unused
    handle_info/3,          % required by the gen_fsm behaviour, unused
    code_change/4           % required by the gen_fsm behaviour, unused
]).



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%  defines and records
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-define(MAIN_FUNCTION_NAME, "execute").


%% barrier object on which processors can synchronise
-record(barrierQueue, {
    uid         :: reference(), % id of this barrier
    waiters =[] :: [pid()],     % processors already waiting on this barrier
    missing     :: integer()    % number of processors that need to sync on this barrier
                                %  before it can be released
}).


%% a collection of all args ever received by the manager
-record(args, {
    program_ast     = none,
    input_server    = none,
    output_server   = none,
    supervisor      = none,
    mem_model       = none,
    callback        = fun() -> ok end  % "empty" method
}).


%% stats collected during the proper execution phase
-record(stats, {
    cycles          = 0,    % number of time units elapsed
    work            = 0,    % number of operations performed
    cost            = 0,    % cumulative number of time units used by all processors
    max_processors  = 0     % maximum number of processors executing simultaneously
}).


%% a manager's state
-record(mState, {
    memory                  :: pid(),   % global memory manager
    on_clock        = []    :: [pid()], % processors waiting for a clock signal (a tick)
    barrier_reqs    = []    :: [pid()], % processors waiting to obtain a new barrier object
    on_barriers     = []    :: [#barrierQueue{}],  % processors synchronizing on barriers
    running         = 0     :: non_neg_integer(), % number of processors that are active
                                              %  (not waiting in a call to the manager)
    processors      = []    :: [pid()], % processors registered within this manager
    suspended_proc  = []    :: [pid()], % processors that started a parallel block
    stats           = #stats{},         % execution stats
    all_args                :: #args{}
}).


%% arguments for the pre-execution phase
-record(preexecutionArgs, {
    program_ast         :: #rProgram{}, % program with declarations to process
    data_source         :: pid(),       % io_server to read input
    memory_to_fill      :: pid(),       % memory to fill with vars (along with scope)
    scope_to_fill       :: pid(),       % scope to fill with vars (along with memory)
    processor           :: pid()        % processor to evaluate referenced vars
}).



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%  public API (for users)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

start_link(Sup = {supervisor, _S}) ->
    logger:log("start link", ?MODULE),
    % start the FSM
    ImplModule = ?MANAGER_IMPL_MODULE,
    {ok, _Manager} = gen_fsm:start_link(ImplModule, _Arg=Sup, _Opts=[]).


%%--------------------------------------------------------------------
%% @doc
%% Performs the pre-execution phase of program using data from input server.
%%
%% Pre-execution consists of extracting from the program functions,
%% variable declarations and variable loads. Variables are loaded in the
%% order of appearance. All global variables are prepared.
%%
%% @end
%%--------------------------------------------------------------------
prepare(Manager, Program, InputServer, MemoryModel) ->
    case send_sync(Manager, {prepare, Program, InputServer, MemoryModel}) of
        ok ->
            ok
    end.


%%--------------------------------------------------------------------
%% @doc
%% Starts the proper-execution phase
%%
%% During that phase synchronisation and memory monitoring are enabled.
%%
%% @end
%%--------------------------------------------------------------------
launch(Manager, Callback) ->
    case send_sync(Manager, {launch, Callback}) of
        ok ->
            ok
    end.


%%--------------------------------------------------------------------
%% @doc
%% Returns stats for the proper-execution phase.
%%
%% Returns the number of cycles the execution lasted, the quantity of
%% work done (counted as the number of operations), the cost of work
%% (counted as the total number of cycles used per processor), and the
%% maximum number of processors used (allocated) at a given time.
%%
%% All those values refer to the proper-execution phase.
%%
%% To get stats, the proper-execution phase must first finish.
%%
%% @end
%%--------------------------------------------------------------------
get_stats(Manager) ->
    case send_sync(Manager, get_stats) of
        {ok, Stats} ->
            {ok, Stats}
    end.


%%--------------------------------------------------------------------
%% @doc
%% Causes output data to be written to the given output server.
%%
%% @end
%%--------------------------------------------------------------------
write_output(Manager, OutputServer) ->
    case send_sync(Manager, {write_output, OutputServer}) of
        {err, Error} ->
            {err, Error};
        ok ->
            ok
    end.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%  gen_fsm states
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

is_new({prepare, Program, InputServer, MemoryModel}, _From, State)
    when State#mState.all_args#args.input_server == none ->
    logger:log_enter("<is_new>: prepare", ?MODULE),
    Supervisor = State#mState.all_args#args.supervisor,
    % during pre-execution no memory model is needed
    Memory = create_memory(_Model=none, Supervisor),
    Scope = create_scope(Program, Supervisor),
    Processor = create_processor("pre-exec", Scope, Memory, Supervisor),

    % process global var declaration and load statements
    perform_preexecution(#preexecutionArgs{
        program_ast = Program,
        data_source = InputServer,
        scope_to_fill = Scope,
        memory_to_fill = Memory,
        processor = Processor}),

    Args_1 = State#mState.all_args#args{
        program_ast = Program,
        mem_model = MemoryModel,
        input_server = InputServer},
    State_1 = State#mState{
        memory = Memory,
        all_args = Args_1},

    logger:log_exit(?MODULE),
    {reply, ok, is_ready, {State_1, Processor}}.


is_ready({launch, Callback}, _From, {State, Processor}) when is_function(Callback, 0) ->
    logger:log("<is_ready>: proper-execution", ?MODULE),

    Memory = State#mState.memory,
    MemModel = State#mState.all_args#args.mem_model,
    mem:set_memory_model(Memory, MemModel),

    processor:set_name_and_manager(Processor, "M", self()),
    launch_proper_execution(Processor),

    State_1 = State#mState{
        all_args = State#mState.all_args#args{
            callback = Callback}},

    logger:log("<is_ready>: proper-execution started", ?MODULE),
    {reply, ok, is_working, State_1}.


is_working(sync_on_tick, From, State) ->
    State_1 = State#mState{
            on_clock = [From | State#mState.on_clock],
            running = State#mState.running - 1},
    State_2 = emit_if_ready(State_1),
    {next_state, is_working, State_2};

is_working(request_barrier, From, State) ->
    State_1 = State#mState{
            barrier_reqs = [From | State#mState.barrier_reqs],
            running = State#mState.running - 1},
    State_2 = emit_if_ready(State_1),
    {next_state, is_working, State_2};

is_working({sync_on_barrier, SenderUid}, From, State) ->
    % TODO?: check if pid is already waiting on some barrier
    Barrier = findBarrierById(SenderUid, State#mState.on_barriers),
    Barrier_1 = Barrier#barrierQueue{
            waiters = [From | Barrier#barrierQueue.waiters],
            missing = Barrier#barrierQueue.missing - 1},
    State_1 = State#mState{
            on_barriers = updateBarrier(Barrier_1, State#mState.on_barriers),
            running = State#mState.running - 1},
    State_2 = emit_if_ready(State_1),
    {next_state, is_working, State_2};

is_working({add_processor, ProcessorPid}, _From, State) ->
    logger:log("<is_working>: RCV add_processor", ?MODULE),
    case lists:member(ProcessorPid, State#mState.processors) of
        true ->
            logger:log("<is_working>: add processor: already registered", ?MODULE),
            {reply, processor_already_registered, is_working, State};
        false ->
            logger:log("<is_working>: add processor: ok, adding", ?MODULE),
            Processors_1 = [ProcessorPid | State#mState.processors],
            AccountableProcessors = length(Processors_1) - length(State#mState.suspended_proc),
            State_1 = State#mState{
                stats = update_stats(State#mState.stats, 0, 0, 0, AccountableProcessors),
                running = State#mState.running + 1,
                processors = Processors_1},
            {reply, ok, is_working, State_1}
    end;

is_working({remove_processor, ProcessorPid}, _From, State) ->
    logger:log("<is_working>: RCV remove processor", ?MODULE),
    case lists:member(ProcessorPid, State#mState.processors) of
        false ->
            {reply, processor_not_registered, is_working, State};
        true ->
            PrunedProcessors = lists:delete(ProcessorPid, State#mState.processors),
            State_1 = State#mState{
                running = State#mState.running - 1,
                processors = PrunedProcessors},
            logger:log("<is_working> current processors: ~p", ?MODULE, [PrunedProcessors]),
            case PrunedProcessors of
                [] ->
                    % allow memory to do its last memory model surveillance check
                    ok = mem:deliver_clock_event(State#mState.memory),
                    % call the "on finish callback" asynchronously
                    OnFinishCallback = State#mState.all_args#args.callback,
                    spawn(fun() -> OnFinishCallback() end),
                    {reply, ok, is_finished, State_1};
                [_|_] ->
                    State_2 = emit_if_ready(State_1),
                    {reply, ok, is_working, State_2}
            end
    end;

is_working({suspend_processor, ProcessorPid}, _From, State) ->
    logger:log("<is_working>: RCV suspend processor", ?MODULE),
    SuspendedProcessors = State#mState.suspended_proc,
    case lists:member(ProcessorPid, State#mState.processors) of
        false ->
            {reply, processor_not_registered, is_working, State};
        true ->
            case lists:member(ProcessorPid, SuspendedProcessors) of
                true ->
                    {reply, processor_already_suspended, is_working, State};
                false ->
                    State_1 = State#mState{
                        suspended_proc = [ProcessorPid | SuspendedProcessors]},
                    {reply, ok, is_working, State_1}
            end
    end;

is_working({unsuspend_processor, ProcessorPid}, _From, State) ->
    logger:log("<is_working>: RCV unsuspend processor", ?MODULE),
    SuspendedProcessors = State#mState.suspended_proc,
    case lists:member(ProcessorPid, SuspendedProcessors) of
        false ->
            {reply, processor_not_suspended, is_working, State};
        true ->
            State_1 = State#mState{
                suspended_proc = lists:delete(ProcessorPid, SuspendedProcessors)},
            {reply, ok, is_working, State_1}
    end.


is_finished(get_stats, _From, State) ->
    Stats = [
        {cycles, State#mState.stats#stats.cycles},
        {work, State#mState.stats#stats.work},
        {cost, State#mState.stats#stats.cost},
        {max_processors, State#mState.stats#stats.max_processors}],
    {reply, {ok, Stats}, is_finished, State};

is_finished({write_output, OutputServer}, _From, State) ->
    logger:log_enter("<is_finished>: writing output", ?MODULE),
    {ok, AllVars} = mem:get_all_variables(State#mState.memory),
    Output = [ {lists:reverse(Addr), Val} ||
        Var = #variable{value = Val, name = #var_addr{addr = Addr}} <- AllVars,
        Var#variable.isOutputVar == true ],
    SortedOutput = lists:sort(Output),

    try
        lists:foreach(
            fun
                ({VarAddr, undefined}) ->
                    throw({not_initialised, VarAddr});
                ({_, VarValue}) ->
                    RawValue = VarValue#rConstVal.val,
                    io_server:write_int(OutputServer, RawValue)
            end,
            SortedOutput),

        State_1 = State#mState{
            all_args = State#mState.all_args#args{
                output_server = OutputServer}},

        logger:log_exit("             writing done", ?MODULE),
        {reply, ok, is_finished, State_1}
    catch
        throw:Error ->
            logger:log_exit("             writing finished with errors", ?MODULE),
            {reply, {err, Error}, is_finished, State}
    end.

is_finished(terminate, State) ->
    logger:log("<is_finished>: terminating~n~n", ?MODULE),
    {stop, user_called_terminate, State}.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%  public API (for subscribers)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%--------------------------------------------------------------------
%% @doc
%% Causes the caller to synchronize on a tick event.
%%
%% This function will not return until all running (not already syncing)
%% processors call {@link sync_on_tick/1} or {@link sync_on_barrier/2}.
%%
%% @end
%%--------------------------------------------------------------------
sync_on_tick(Manager) ->
    case send_sync(Manager, sync_on_tick) of
        tick ->
            ok
    end.


%%--------------------------------------------------------------------
%% @doc
%% Causes the caller to synchronize on a barrier request event.
%%
%% This function will not return until all running (not already syncing)
%% processors call {@link request_barrier/1} or {@link sync_on_barrier/2}.
%%
%% @end
%%--------------------------------------------------------------------
request_barrier(Manager) ->
    case send_sync(Manager, request_barrier) of
        {barrier, BarrierUid} ->
            {ok, {barrier, BarrierUid}}
    end.


%%--------------------------------------------------------------------
%% @doc
%% Causes the caller to synchronize on a barrier sync event.
%%
%% This function will not return until all running (not already syncing)
%% processors call {@link sync_on_barrier/2}.
%%
%% @end
%%--------------------------------------------------------------------
sync_on_barrier(Manager, {barrier, BarrierUid}) ->
    case send_sync(Manager, {sync_on_barrier, BarrierUid}) of
        release_barrier ->
            ok
    end.


%%--------------------------------------------------------------------
%% @doc
%% Registers in the given manager for sync and stats purposes.
%%
%% After calling this function the processor can synchronise in the
%% manager. Moreover, it will be also accounted for execution stats.
%%
%% A call to this function should be paired with a corresponding
%% call to {@link unregister_processor/2}
%%
%% @end
%%--------------------------------------------------------------------
register_processor(Manager, ProcessorPid) when is_pid(Manager), is_pid(ProcessorPid) ->
    logger:log_enter("register processor (API): proc=~p", ?MODULE, [ProcessorPid]),
    case send_sync(Manager, {add_processor, ProcessorPid}) of
        ok ->
            logger:log_exit(?MODULE),
            ok;
        processor_already_registered ->
            logger:log_exit("~p", ?MODULE, [processor_already_registered]),
            throw(processor_already_registered);
        Other ->
            logger:log_exit("register processor (API): ERROR got: ~p", {?MODULE, 'ERROR'},
                    [Other]),
            throw("manager:register_processor - received an unrecognized pattern")
    end.


%%--------------------------------------------------------------------
%% @doc
%% Unregisters in the given manager.
%%
%% After calling this function the processor should no longer ask for
%% synchronisation events. Also, it will no longer be accounted for stats.
%%
%% A call to this function should be paired with a corresponding
%% call to {@link register_processor/2}
%%
%% @end
%%--------------------------------------------------------------------
unregister_processor(Manager, ProcessorPid) when is_pid(Manager), is_pid(ProcessorPid) ->
    logger:log_enter("unregister processor (API): proc=~p", ?MODULE, [ProcessorPid]),
    case send_sync(Manager, {remove_processor, ProcessorPid}) of
        ok ->
            logger:log_exit(?MODULE),
            ok;
        processor_not_registered ->
            logger:log_exit("~p", ?MODULE, [processor_not_registered]),
            throw(processor_not_registered);
        Other ->
            logger:log_exit("unregister processor (API): ERROR got: ~p", ?MODULE, [Other]),
            throw("manager:unregister_processor - received an unrecognized pattern")
    end.


% todo: edoc
suspend_registration(Manager, ProcessorPid) when is_pid(Manager), is_pid(ProcessorPid) ->
    logger:log("suspend processor (API)", ?MODULE),
    case send_sync(Manager, {suspend_processor, ProcessorPid}) of
        processor_not_registered ->
            throw(processor_not_registered);
        processor_already_suspended ->
            logger:log("processor already suspended: ~p", {?MODULE, 'WARN'}, [ProcessorPid]),
            throw(processor_already_suspended);
        ok ->
            ok
    end.


% todo: edoc
resume_registration(Manager, ProcessorPid) when is_pid(Manager), is_pid(ProcessorPid) ->
    logger:log("unsuspend processor (API)", ?MODULE),
    case send_sync(Manager, {unsuspend_processor, ProcessorPid}) of
        processor_not_suspended ->
            throw(processor_not_suspended);
        ok ->
            ok
    end.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%  gen_fsm callbacks
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

init({supervisor, Supervisor}) ->
    logger:log("init", ?MODULE),
    State = #mState{all_args = #args{
        supervisor = Supervisor}},
    {ok, is_new, State};
init(_) ->
    logger:log("invalid args' list in ~p:init/1", {?MODULE, 'ERROR'}, [?MODULE]).


terminate({bad_return_value, Tuple}, StateName, State) when element(1,Tuple)==memory_model_violation ->
            io:format("~n##########~nCODE EXECUTION ABORTED~n"
            "  REASON:  ~70P ~n##########~n~n", [Tuple, 20]);

terminate({bad_return_value, Reason}, StateName, State) ->
    logger:log("terminate for reason - bad_return_value:", ?MODULE),
    logger:log("      ~150P", ?MODULE, [Reason, 20]),
    logger:log("  in state: ~p", ?MODULE, [StateName]),
    logger:log("  with data: ~150P", ?MODULE, [State, 20]);

terminate(Reason, StateName, State) ->
    logger:log("terminate for reason:", ?MODULE),
    logger:log("      ~150P", ?MODULE, [Reason, 20]),
    logger:log("  in state: ~p", ?MODULE, [StateName]),
    logger:log("  with data: ~150P", ?MODULE, [State, 20]).


handle_event(Event, _StateName, State) ->
    logger:log("handle event - not expected", {?MODULE, 'ERROR'}),
    logger:log("    with event: ~p", {?MODULE, 'ERROR'}, [Event]),
    {stop, unexpected, State}.


handle_sync_event(Event, _From, _StateName, State) ->
    logger:log("handle sync event - not expected", {?MODULE, 'ERROR'}),
    logger:log("    with event: ~p", {?MODULE, 'ERROR'}, [Event]),
    {stop, unexpected, ok, State}.


handle_info(Info, _StateName, State) ->
    logger:log("handle info - not expected", {?MODULE, 'ERROR'}),
    logger:log("    with info: ~p", {?MODULE, 'ERROR'}, [Info]),
    {stop, unexpected, State}.


code_change(_OldVsn, StateName, State, _Extra) ->
    logger:log("code change - not expected", {?MODULE, 'ERROR'}),
    {ok, StateName, State}.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%  internal functions
%%%  (for pre-execution phase)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

create_memory(MemoryModel, Supervisor) ->
    MemChildSpec = {
        global_memory,
        {mem, start_link, _Args=[MemoryModel]},
        ?WORKER_RESTART_STRATEGY,
        ?WORKER_SHUTDOWN_TIMEOUT,
        worker,
        [mem, ?MEM_IMPL_MODULE]
    },
    {ok, Memory} = supervisor:start_child(Supervisor, MemChildSpec),
    Memory.


create_scope(#rProgram{sttmnts = GlobalStatements}, Supervisor) ->
    Functions = [Sttmnt || Sttmnt <- GlobalStatements, is_record(Sttmnt, rFunctionDef)],
    ScopeChildSpec = {
        main_scope,
        {scope, start_link, _Args=[]},
        ?WORKER_RESTART_STRATEGY,
        ?WORKER_SHUTDOWN_TIMEOUT,
        worker,
        [scope, ?SCOPE_IMPL_MODULE]
    },

    % start scope
    {ok, Scope} = supervisor:start_child(Supervisor, ScopeChildSpec),
    scope:open_frame(Scope),

    % fill with functions
    lists:foreach(
        fun(Fun) ->
            scope:add_fun(Scope, Fun)
        end,
        Functions),

    Scope.


create_processor(Name, Scope, Memory, Supervisor) ->
    ProcessorChildSpec = {
        main_processor,
        {processor, start_link, _Args=[Supervisor]},
        ?WORKER_RESTART_STRATEGY,
        ?WORKER_SHUTDOWN_TIMEOUT,
        worker,
        [processor, ?PROCESSOR_IMPL_MODULE]
    },

    {ok, Processor} = supervisor:start_child(Supervisor, ProcessorChildSpec),
    processor:prepare(Processor, Name, Scope, no_manager, Memory),

    Processor.


perform_preexecution(#preexecutionArgs{program_ast = Program, data_source = InputServer,
        scope_to_fill = Scope, memory_to_fill = Memory, processor = Processor})
    when is_record(Program, rProgram), is_pid(InputServer), is_pid(Scope), is_pid(Memory),
        is_pid(Processor) ->
    logger:log_enter("perform pre-execution", ?MODULE),
    DeclarationsAndLoads = extract_decls_and_loads(Program),

    % iterate over var declarations and var loads in the order of their appearance
    lists:foldl(
        fun
            (VarDecl, InitialisedButNotLoaded) when is_record(VarDecl, rVarDecl) ->
                VarName = VarDecl#rVarDecl.ident,
                logger:log_enter("var decl  ~p", ?MODULE, [VarName]),
                {ok, Cells, Type} = process_global_var_decl(VarDecl, Scope, Memory, Processor),
                logger:log_exit(?MODULE),
                dict:store(VarName, {Cells, Type}, InitialisedButNotLoaded);
            (VarLoad, ProcessedButNotLoaded) when is_record(VarLoad, rVarLoad) ->
                VarName = VarLoad#rVarLoad.ident,
                logger:log_enter("var load  ~p", ?MODULE, [VarName]),
                {Cells, Type} =
                    case dict:find(VarName, ProcessedButNotLoaded) of
                        {ok, {CellsForVar, VarType}} ->
                            {CellsForVar, VarType};
                        error ->
                            % var was not defined or is already loaded
                            throw({cannot_load_var, {var_name, VarName}})
                    end,
                lists:foreach(
                    fun(VarAddr) ->
                        load_var_cell(Type, VarAddr, InputServer, Memory)
                    end,
                    Cells),
                logger:log_exit(?MODULE),
                % once loaded a var cannot be loaded again
                dict:erase(VarName, ProcessedButNotLoaded)
        end,
        dict:new(),  % vars that were prepared thus can be loaded
        DeclarationsAndLoads),

    logger:log_exit(?MODULE),
    ok.


process_global_var_decl(VarDecl, Scope, Memory, Processor)
    when is_record(VarDecl, rVarDecl) ->
    logger:log_enter("process global var decl for ~p", ?MODULE, [VarDecl#rVarDecl.ident]),

    % extract properties and make sure 'global' is amongst them
    VarProperties = util:extract_var_properties(VarDecl),
    true = lists:member(global, VarProperties),

    % evaluate (simplify) the type before using it - compute arrays' ranges
    EvType = make_type_canonical(VarDecl#rVarDecl.type, Processor),
    VarDecl_1 = VarDecl#rVarDecl{type = EvType},

    VarAddrList = util:dereference_decl(VarDecl_1),
    VarType = util:get_base_type(EvType),

    logger:log("processing var decl  type: ~150p", ?MODULE, [VarType]),
    logger:log("      var addr list:  ~150P", ?MODULE, [VarAddrList, 7]),

    % add var to scope and memory
    lists:foreach(
        fun(VarAddr) ->
            % as 'global' is in VarProperties all accesses to the var will be redirected to mem
            scope:add_var(Scope, VarAddr, VarType, VarProperties),
            mem:add_var({VarType, VarAddr}, Memory, VarProperties)
        end,
        VarAddrList),

    % compute var value if initialisation expression is present
    InitExpr = VarDecl#rVarDecl.val,
    case {EvType, InitExpr} of
        {_, empty} ->
            % no initialisation expression
            ok;
        {#rSimpleVarType{}, Expression} ->
            % compute the value
            {ok, Value} = processor:evaluate(Processor, Expression),
            % and ensure it is assignable to the var (here, just simplified to type equality)
            VarType = Value#rConstVal.type,

            logger:log("initialising with:  ~150p", ?MODULE, [Value]),

            % the type is rSimpleVarType so exactly one VarAddr is produced
            [VarAddr] = VarAddrList,
            ok = mem:write_var({VarAddr, Value}, Memory);
        {#rArrayVarType{}, Expression} ->
            throw({arrays_cannot_be_initialised, {var_name, VarDecl#rVarDecl.ident},
                {got, Expression}, {expected, empty}})
    end,

    logger:log_exit(?MODULE),
    {ok, VarAddrList, VarType}.


load_var_cell(_CellType, _CellAddr, no_input, _Memory) ->
    % called when processing global var declaration but not loading that var
    ok;
load_var_cell(CellType, CellAddr, InputServer, Memory) when is_pid(InputServer) ->
    logger:log_enter("loading global var cell: ~p", ?MODULE, [CellAddr]),
    % TODO: add here more types when those are supported by the rest of the implementation
    case CellType of
        ?INT ->
            {ok, CellRawValue} = io_server:read_int(InputServer)
    end,
    CellValue = #rConstVal{type = CellType, val = CellRawValue},
    ok = mem:write_var({CellAddr, CellValue}, Memory),
    logger:log_exit(?MODULE),
    ok.


extract_decls_and_loads(#rProgram{sttmnts = GlobalStatements}) ->
    [ Sttmnt || Sttmnt <- GlobalStatements,
        is_record(Sttmnt, rVarLoad) orelse is_record(Sttmnt, rVarDecl) ].


make_type_canonical(VarType, _Processor)
    when is_record(VarType, rSimpleVarType) ->
    VarType;
make_type_canonical(VarType, Processor)
    when is_record(VarType, rArrayVarType) ->
    EvBaseType = make_type_canonical(VarType#rArrayVarType.baseType, Processor),
    RangeBegin = VarType#rArrayVarType.range#rRange.'begin',
    RangeEnd = VarType#rArrayVarType.range#rRange.'end',

    {ok, EvBegin} = processor:evaluate(Processor, RangeBegin),
    {ok, EvEnd} = processor:evaluate(Processor, RangeEnd),

    #rArrayVarType{
        range = #rRange{'begin' = EvBegin, 'end' = EvEnd},
        baseType = EvBaseType}.


launch_proper_execution(Processor) ->
    logger:log("launching proper execution on processor", ?MODULE),

    % prepare a call to the "execute" function
    FunName = util:make_string(?MAIN_FUNCTION_NAME),
    LaunchFunCall = #rFunctionCall{name = FunName, args = []},

    OnFinishCallback = fun() -> ok end,
    % this call is made asynchronously to avoid a deadlock; in a processor we'd like to
    %  wait for a reply (to make sure everything is properly synchronised) but when we start
    %  the _first_ processor it will have to wait anyway until the manager is ready
    spawn(fun() -> processor:run_async(Processor, LaunchFunCall, OnFinishCallback) end),
    ok.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%  internal functions
%%%  (for proper-execution phase)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% all active processors are waiting for a clock signal
emit_if_ready(S=#mState{running = 0, on_clock = OnClock, barrier_reqs = []})
        when OnClock =/= [] ->
    logger:log_enter("emit if ready - clock sync", ?MODULE),
    ok = mem:deliver_clock_event(S#mState.memory),
    reply_all(OnClock, tick),
    CycleCost = length(S#mState.processors) - length(S#mState.suspended_proc),
    Stats_1 = update_stats(S#mState.stats, 1, _CycleWork=length(OnClock), CycleCost, 0),
    logger:log_exit(?MODULE),
    S#mState{
        stats = Stats_1,
        running = length(OnClock),
        on_clock = []};

% all active processors are waiting to obtain a new barrier object
emit_if_ready(S=#mState{running = 0, on_clock = [], barrier_reqs = BarrReqs})
        when BarrReqs =/= [] ->
    logger:log_enter("emit if ready - new barrier", ?MODULE),
    BarrUid = make_ref(),
    Barrier = {barrier, BarrUid},
    reply_all(BarrReqs, Barrier),
    NewBarrierQueue = #barrierQueue{uid = BarrUid, missing = length(BarrReqs)},
    logger:log_exit(?MODULE),
    S#mState{
        running = length(BarrReqs),
        barrier_reqs = [],
        on_barriers = [NewBarrierQueue | S#mState.on_barriers]};

% no active processors, all are waiting to sync on a barrier
emit_if_ready(S=#mState{running = 0, on_clock = [], barrier_reqs = [],
        on_barriers = OnBarriers}) ->
    logger:log_enter("emit if ready - barrier sync", ?MODULE),
    % The first (most recently created) ready barrier will be used. This ensures that
    %  all barriers inside a block are processed before barriers outside that block.
    ReadyBarrier = findFirstReadyBarrier(OnBarriers),
    reply_all(ReadyBarrier#barrierQueue.waiters, release_barrier),
    logger:log_exit(?MODULE),
    S#mState{
        running = length(ReadyBarrier#barrierQueue.waiters),
        on_barriers = OnBarriers -- [ReadyBarrier]};

% some processors are still running
emit_if_ready(State=#mState{running = RunningProcessors})
        when RunningProcessors>0 ->
    logger:log_enter("emit if ready - not ready", ?MODULE),
    % do nothing, continue until all processors are waiting for the manager
    %  to emit an event
    logger:log_exit(?MODULE),
    State;

emit_if_ready(S=#mState{}) ->
    % If execution came here it means that both "on_clock" and "barrier_reqs" are
    %  non-empty which means that active processors were not executing the exact-same
    %  part of the program. Such a situation is not permitted in parallel systems.
    logger:log("ERROR:  unrecognized state pattern in 'emit': ~p", {?MODULE, 'ERROR'}, [S]),
    throw({unrecognized_state_pattern, S});

emit_if_ready(_) ->
    throw(badarg).


findFirstReadyBarrier([]) ->
    throw(barrier_not_found);
findFirstReadyBarrier([Barrier | _BarriersList])
        when Barrier#barrierQueue.missing == 0 ->
    Barrier;
findFirstReadyBarrier([_Barrier | BarriersList]) ->
    findFirstReadyBarrier(BarriersList).


findBarrierById(_Id, []) ->
    throw(barrier_not_found);
findBarrierById(Id, [Barrier | BarriersList]) ->
    case Barrier#barrierQueue.uid of
        Id ->
            Barrier;
        _ ->
            findBarrierById(Id, BarriersList)
    end.


updateBarrier(_NewBarrier, []) ->
    throw(barrier_not_found);
updateBarrier(NewBarrier, [Barrier | BarriersList])
        when is_record(NewBarrier, barrierQueue) ->
    BarrierId = NewBarrier#barrierQueue.uid,
    case Barrier#barrierQueue.uid of
        BarrierId ->
            [NewBarrier | BarriersList];
        _ ->
            [Barrier | updateBarrier(NewBarrier, BarriersList)]
    end.


update_stats(Stats, AddedCycles, AddedWork, AddedCost, NumProcessors)
    when is_record(Stats, stats) ->
    OldCycles = Stats#stats.cycles,
    OldWork = Stats#stats.work,
    OldCost = Stats#stats.cost,
    OldNumProcessors = Stats#stats.max_processors,
    Stats#stats{
        cycles = OldCycles + AddedCycles,
        work = OldWork + AddedWork,
        cost = OldCost + AddedCost,
        max_processors = max(OldNumProcessors, NumProcessors)
    }.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%  globally useful helpers
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

reply_all(Whos, What) when is_list(Whos) ->
    lists:foreach(
        fun(Who) -> reply(Who, What) end,
        Whos).

reply(Who, What) when not is_list(Who) ->
    gen_fsm:reply(Who, What).
%%     util:reply(Who, What).


send_sync(Who, What) ->
    gen_fsm:sync_send_event(Who, What, ?TIMEOUT).
%%     util:send_sync(Who, What, ?TIMEOUT).

send_async(Who, What) ->
    gen_fsm:send_event(Who, What).
%%     util:send_async(Who, What).
