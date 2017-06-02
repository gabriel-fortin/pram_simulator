%%%-------------------------------------------------------------------
%%% @author Gabriel Fortin
%%% @copyright (C) 2015, Gabriel Fortin
%%% @doc
%%%
%%% @end
%%% Created : 28. May 2015 8:24 PM
%%%-------------------------------------------------------------------
-module(processor).
-author("Gabriel Fortin").

-behaviour(gen_fsm).



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%  includes and exports
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-include("../common/ast.hrl").
-include("../common/defs.hrl").


%% API
-export([
    start_link/1,
    stop/1,
    prepare/4, prepare/5,
    set_name_and_manager/3,
    run_async/3,
    evaluate/2
]).


%% gen_fsm callbacks
-export([
    awaiting_preparation/3,     % gen_fsm state
    awaiting_run/3,             % gen_fsm state
    init/1,
    terminate/3,
    handle_event/3,
    handle_sync_event/4,
    handle_info/3,
    code_change/4
]).



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%  defines and records
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% increment statement for a "while" loop - anything not affecting mem or scope
-define(NULL_INCREMENT, #rConstVal{val = 1, type = ?INT}).


-record(pState, {
    supervisor  :: pid(),
    name        :: any(),  %% user-friendly name (used in logs)
    scope       :: pid(),
    manager     :: pid() | no_manager,  %% during pre-execution no manager needed
    memory      :: pid()
}).



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%  public API (for users)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%--------------------------------------------------------------------
%% @doc
%% Creates an uninitialised processor and returns its pid.
%%
%% The argument is a supervisor that will be used to spawn nested processors.
%%
%% After calling this function a call to {@link prepare/4,5} is expected.
%% @end
%%--------------------------------------------------------------------
start_link(Supervisor) ->
    Arg = {supervisor, Supervisor},
    gen_fsm:start_link(?PROCESSOR_IMPL_MODULE, Arg, _Opts=[]).


prepare(Processor, Scope, Manager, Memory) ->
    ProcessorName = "M",  % main processor
    prepare(Processor, ProcessorName, Scope, Manager, Memory).

prepare(Processor, Name, Scope, Manager, Memory)
    when is_pid(Processor), not is_pid(Name), is_pid(Scope), is_pid(Memory),
         (is_pid(Manager) orelse Manager==no_manager) ->
    Event = {prepare_inject, Name, Scope, Manager, Memory},
    ok = gen_fsm:sync_send_event(Processor, Event).


set_name_and_manager(Processor, Name, Manager) when is_pid(Processor) ->
    Event = {set_name_and_manager, Name, Manager},
    ok = gen_fsm:sync_send_event(Processor, Event).


%%% Registers the processor in its manager synchronously then performs the execution in async.
run_async(Processor, AstNode, OnFinishCallback)
        when is_pid(Processor), is_function(OnFinishCallback, 0) ->
    Event = {run, AstNode, OnFinishCallback},
    ok = gen_fsm:sync_send_event(Processor, Event).


evaluate(Processor, Expression) ->
    % TODO?: ensure that Expression is indeed an expression
    Event = {eval, Expression},
    {ok, _Result} = gen_fsm:sync_send_event(Processor, Event).


stop(Processor) ->
    ok = gen_fsm:sync_send_all_state_event(Processor, stop).



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%  gen fsm states
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

awaiting_preparation({prepare_inject, Name, Scope, Manager, Memory}, _From, {sup, Supervisor}) ->
    ProcName = Name, % "M",  % main processor
    logger:log("prepare_inject", {?MODULE, ProcName}),
    State = #pState{
        supervisor = Supervisor,
        name = ProcName,
        scope = Scope,
        manager = Manager,
        memory = Memory},
    {reply, ok, awaiting_run, State}.


awaiting_run({run, AstNode, Callback}, From, St) ->
    logger:log("will exec", tag(St)),
    logger:log("     with state: ~150p", tag(St), [St]),
    logger:log("     and ast node: ~150P", tag(St), [AstNode, 10]),

    manager:register_processor(St#pState.manager, self()),
    % it's important to reply AFTER registering the processor; otherwise the caller
    %  could prematurely synchronise in the manager - before the manager "knows"
    %  about this processor (thus before it considers it while synchronising)
    %  resulting in a miss-synchronisation of all processors
    gen_fsm:reply(From, ok),
    timer:sleep(100),
    try
        % main execution point
        BlockRetVal = do_exec(St, AstNode),
        case BlockRetVal of
            no_value ->
                ok;
            _ ->
                throw({processor_block_should_not_return_value, {expected, no_value},
                    {got, BlockRetVal}})
        end
    catch
        throw:T ->
            io:format("~n##########~nCODE EXECUTION ABORTED ON PROCESSOR ~p~n"
            "  REASON: ~p~n##########~n~n", [St#pState.name, T])
    end,
    manager:unregister_processor(St#pState.manager, self()),

    Callback(),
    {stop, _Reason={shutdown, execution_ended}, St};  % terminate/3 will be called

awaiting_run({set_name_and_manager, NewName, NewManager}, _From, St) ->
    logger:log("renaming processor to ~p", tag(St), [NewName]),
    St_1 = St#pState{
        name = NewName,
        manager = NewManager},
    {reply, ok, awaiting_run, St_1};

awaiting_run({eval, Expression}, _From, St) ->
    logger:log("eval: ~150P", tag(St), [Expression, 6]),
    Result = eval(St, Expression),
    {reply, {ok, Result}, awaiting_run, St}.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%  execution of program nodes
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec do_exec(StateIn, Statement) -> Outcome when
            StateIn     :: #pState{},
            Statement   :: tStatement(),
            Outcome     :: no_value | {val, #rConstVal{}} | {return, no_value | #rConstVal{}} |
                           {continue | break, string_type()}.
do_exec(St, #rFunctionCall{name = FunName, args = CallArgs}) ->
    logger:log_enter("DO EXEC FunCall: ~p ~p", tag(St), [FunName, CallArgs]),
    % get function from scope
    {ok, FunDef} = scope:get_fun(St#pState.scope, FunName),
    % unpack it
    DefArgs = FunDef#rFunctionDef.args,
    ExpectedRetType = FunDef#rFunctionDef.retType,
    % compute args' values
    EvaluatedArgs = [ eval(St, Arg) || Arg <- CallArgs ],
    % open frame in scope
    scope:open_frame(St#pState.scope),
    % add computed args to scope
    lists:foreach(
        fun({DefArg, EvArg}) ->
            % unpack args, make sure their types match
            #rVarDecl{type = Type, ident = ArgName} = DefArg,
            #rConstVal{type = Type, val = Value} = EvArg,
            % add them to scope
            ArgAddr = case Type of
                #rSimpleVarType{} ->
                    ArgVar = #rSimpleVariable{name = ArgName},
                    util:dereference(ArgVar);
                #rArrayVarType{} ->
                    % arrays are allowed only in shared memory
                    throw({not_supported, "arrays passed as a function argument"})
            end,
            scope:add_var(St#pState.scope, ArgAddr, Type, []),
            scope:write_var(St#pState.scope, ArgAddr, Value)
        end,
        lists:zip(DefArgs, EvaluatedArgs)),
    wait_for_clock(St),
    % execute the body of the function
    BlockRes = process_code_block(St, FunDef#rFunctionDef.body),
    logger:log("fun call - block res: ~150p", tag(St), [BlockRes]),
    % make sure that fun yields a value iff fun return type is not void
    Res = case {ExpectedRetType, BlockRes} of
        % block finished with no return statement for a void function
        {void, no_value} ->
            no_value;
        % block finished with an empty return statement for a void function
        {void, {return, no_value}} ->
            no_value;
        % block finished with a value of the same type as declared by function
        {RetType, {return, Val}}
            when is_record(Val, rConstVal), Val#rConstVal.type==RetType ->
            {val, Val};
        % block finished with a value of type different than declared by function
        {RetType, {return, Val}}
            when is_record(Val, rConstVal) ->
            throw({function_ends_with_invalid_type_of_return_value, {ret_type_is, RetType},
                {got, type, Val#rConstVal.type}, {fun_name, FunName}});
        % block finished with no return statement but function return type is not void
        {RetType, no_value} ->
            throw({function_ends_with_no_return_value, {expected, RetType}, {fun_name, FunName}});
        {RetType, OtherResult} ->
            throw({function_ends_with_invalid_result, {ret_type_is, RetType},
                    {got, OtherResult}, {fun_name, FunName}})
    end,
    % close frame
    scope:close_frame(St#pState.scope),
    % return result (#rConstVal{})
    logger:log_exit("fun call, returning: ~p", tag(St), [Res]),
    Res;

do_exec(St, #rParallelBlock{args = ParallelArgs, body = Body}) when is_record(Body, rBody) ->
    logger:log_enter("DO EXEC ParBlock:", tag(St)),
    logger:log("        par args = ~p", tag(St), [ParallelArgs]),
    logger:log("        Manager = ~p", tag(St), [St#pState.manager]),
    Supervisor = St#pState.supervisor,
    Manager = St#pState.manager,
    Memory = St#pState.memory,
    Scope = St#pState.scope,
    Name = St#pState.name,

    % make a barrier to wait until the parallel block finishes
    Barrier = request_barrier(St),
    % compute args' values
    EvParallelArgs = lists:map(
        fun(PA=#rParallelArg{range = #rRange{'begin' = Begin, 'end' = End}}) ->
            EvBegin = eval(St, Begin),
            EvEnd = eval(St, End),
            PA#rParallelArg{range = #rRange{'begin' = EvBegin, 'end' = EvEnd}}
        end,
        ParallelArgs),
    % prepare parallel arguments
    AllArgsCombinations = cartesian_product(EvParallelArgs),
    logger:log("cartesian product: ~p", tag(St), [AllArgsCombinations]),
    % foreach args combination set up a processor
    ProcessorPidsAndNames = lists:map(
        fun(ParArgsCombination) ->
            SubName = compute_subname(Name, ParArgsCombination),
            ClonedScope = create_cloned_scope(Supervisor, SubName, Scope),
            fill_scope_with_parargs(ClonedScope, ParArgsCombination),

            Processor = create_processor(Supervisor, SubName, ClonedScope, Manager, Memory),
            {Processor, SubName}
        end,
        AllArgsCombinations),

    % after ALL processors are prepared, execution on them can be started
    logger:log("do exec: par block, starting processors", tag(St)),
    manager:suspend_registration(Manager, self()),
    Callback = fun() -> ok end,
    lists:foreach(
        fun({Pid, _}) -> processor:run_async(Pid, Body, Callback) end,
        ProcessorPidsAndNames),
    % wait for all processors in the parallel block to finish
    sync_on_barrier(St, Barrier),

    wait_for_processors_to_terminate([P || {P, _} <- ProcessorPidsAndNames]),

    % remove processors from supervisor
    lists:foreach(
        fun({_, ProcName}) ->
            supervisor:delete_child(Supervisor, process_id(processor, ProcName))
        end,
        ProcessorPidsAndNames),

    manager:resume_registration(Manager, self()),
    logger:log_exit(tag(St)),
    % a parallel block produces no value to be returned
    no_value;

do_exec(St, Variable) when is_record(Variable, rSimpleVariable) or is_record(Variable, rArrayElement) ->
    logger:log_enter("DO EXEC Var  ~150p", tag(St), [Variable]),
    wait_for_clock(St),
    VarAddr = util:dereference(eval_indices(St, Variable)),
    {Value, Type} = case scope:read_var_and_type(St#pState.scope, VarAddr) of
        {ok, V, T} ->
            {V, T};
        {err, global_var} ->
            {ok, {_Type, #rConstVal{type=T, val=V}}} = mem:read_var(VarAddr, St#pState.memory),
            {V, T}
    end,
    logger:log_exit("do exec Var: ~150p => ~150p", tag(St), [VarAddr, Value]),
    {val, #rConstVal{type = Type, val = Value}};

do_exec(_St, CV) when is_record(CV, rConstVal) ->
    {val, CV};

do_exec(St, #rUnaryExpr{op = Operator, arg = A}) ->
    logger:log_enter("DO EXEC unary expr:  ~p  ~p", tag(St), [Operator, A]),
    Arg = eval(St, A),
    wait_for_clock(St),
    Value = apply_operator(Operator, Arg),
    logger:log_exit("unary expr => ~p", tag(St), [Value]),
    {val, Value};

do_exec(St, #rBinaryExpr{op = Operator, left = L, right = R}) ->
    logger:log_enter("DO EXEC bin expr:  ~150P  ~150p  ~150P", tag(St), [L, 4, Operator, R, 4]),
    LeftArg = eval(St, L),
    RightArg = eval(St, R),
    wait_for_clock(St),
    logger:log("bin expr:  ~150p  ~150p  ~150p", tag(St), [LeftArg, Operator, RightArg]),
    Value = apply_operator(Operator, LeftArg, RightArg),
    logger:log_exit("bin expr => ~150p", tag(St), [Value]),
    {val, Value};

do_exec(St, #rAssignment{var = Var, val = Val}) ->
    logger:log_enter("DO EXEC assign:  ~150p", tag(St), [Var]),
    logger:log("     val: ~150P", tag(St), [Val, 5]),

    Addr = util:dereference(eval_indices(St, Var)),

    % compute value
    Value = eval(St, Val),

    % write value
    wait_for_clock(St),
    try
        scope:write_var(St#pState.scope, Addr, Value#rConstVal.val)
    catch
        throw:{global_var, _} ->
            mem:write_var({Addr, Value}, St#pState.memory)
    end,

    logger:log_exit("do exec assign, finished: ~150p := ~150p (~150p)", tag(St),
        [Addr, Value#rConstVal.val, Value#rConstVal.type#rSimpleVarType.typeName]),
    {val, Value};

do_exec(St, #rIfInstr{'cond' = Condition, then = ThenBranch, else = ElseBranch}) ->
    logger:log_enter("DO EXEC if instr", tag(St)),
    Scope = St#pState.scope,

    % create barriers
    ThenBarrier = request_barrier(St),
    ElseBarrier = request_barrier(St),

    % open scope frame for the whole instruction
    scope:open_frame(Scope),

    % execute depending on condition
    {val, ConditionResult} = do_exec(St, Condition),
    wait_for_clock(St),

    case ConditionResult of
        ?TRUE ->
            logger:log("if instr: executing -true- branch", tag(St)),
            ExecRes = do_exec(St, ThenBranch),
            sync_on_barrier(St, ThenBarrier);
        ?FALSE ->
            sync_on_barrier(St, ThenBarrier),
            logger:log("if instr: executing -false- branch", tag(St)),
            ExecRes = do_exec(St, ElseBranch)
    end,
    sync_on_barrier(St, ElseBarrier),

    % close scope frame
    scope:close_frame(Scope),
    logger:log_exit("if instr - finished (branch: ~p) => ~150p", tag(St),
        [ConditionResult#rConstVal.val, ExecRes]),
    ExecRes;

do_exec(St, WL) when is_record(WL, rWhileLoop) ->
    logger:log_enter("DO EXEC while loop", tag(St)),

    Barrier = request_barrier(St),

    % execute the loop
    LoopProcessingResult = exec_loop(St, make_loop_args(WL)),

    % sync exit with other processors
    sync_on_barrier(St, Barrier),

    logger:log_exit("while loop => ~p", tag(St), [LoopProcessingResult]),
    LoopProcessingResult;

do_exec(St, FL) when is_record(FL, rForLoop) ->
    logger:log_enter("DO EXEC for loop", tag(St)),
    Scope = St#pState.scope,
    VarInit = FL#rForLoop.varInit,

    Barrier = request_barrier(St),

    % prepare the looping var (nest scope then execute var's declaration)
    scope:open_frame(Scope),
    do_exec(St, VarInit),
    logger:log("do exec for loop - var init done", tag(St)),

    % execute the loop
    LoopProcessingResult = exec_loop(St, make_loop_args(FL)),

    % leave (looping var's) scope and sync exit with other processors
    scope:close_frame(Scope),
    sync_on_barrier(St, Barrier),

    logger:log_exit("for loop => ~p", tag(St), [LoopProcessingResult]),
    LoopProcessingResult;

do_exec(St, #rVarDecl{type = VarType, val = Value} = VD) ->
    logger:log_enter("DO EXEC var decl  ~p", tag(St), [VD#rVarDecl.ident]),
    Scope = St#pState.scope,
    wait_for_clock(St),

    % expect exactly one address from dereferencing
    %  (as during execution creation of arrays is not permitted)
    [VarAddr] = util:dereference_decl(VD),

    % add var to scope
    VarProps = util:extract_var_properties(VD),
    scope:add_var(Scope, VarAddr, VarType, VarProps),

    % write value to scope (if value present)
    case Value of
        empty ->
            ok;
        Val ->
            EvVal = eval(St, Val),
            scope:write_var(Scope, VarAddr, EvVal#rConstVal.val)
    end,

    logger:log_exit(tag(St)),
    no_value;

do_exec(St, #rLoopControl{instr = ControlInstr, label = Label}) ->
    % ControlInstr is either 'break' or 'continue'
    logger:log("loop control: ~p", tag(St), [ControlInstr]),
    wait_for_clock(St),
    {ControlInstr, Label};

do_exec(St, #rReturnInstr{val = ReturnExpr}) ->
    logger:log_enter("return instr", tag(St)),
    case ReturnExpr of
        empty ->
            Res = {return, no_value};
        _ ->
            Res = {return, eval(St, ReturnExpr)}
    end,
    wait_for_clock(St),
    logger:log_exit("return instr => ~p", tag(St), [Res]),
    Res;

do_exec(St, Body) when is_record(Body, rBody) ->
    logger:log_enter("DO EXEC body", tag(St)),

    scope:open_frame(St#pState.scope),
    Result = process_code_block(St, Body),
    scope:close_frame(St#pState.scope),

    logger:log_exit("do exec body  => ~p", tag(St), [Result]),
    Result;

do_exec(_St, UnrecognizedAstNode) ->
    throw({unrecognized_ast_node, UnrecognizedAstNode}).



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%  bin- and unary expressions' helpers
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

apply_operator('+',
    #rConstVal{type = ?INT, val = LeftVal},
    #rConstVal{type = ?INT, val = RightVal})
    when is_integer(LeftVal) andalso is_integer(RightVal) ->
    #rConstVal{type = ?INT, val = LeftVal + RightVal};
apply_operator('-',
    #rConstVal{type = ?INT, val = LeftVal},
    #rConstVal{type = ?INT, val = RightVal})
    when is_integer(LeftVal) andalso is_integer(RightVal) ->
    #rConstVal{type = ?INT, val = LeftVal - RightVal};
apply_operator('*',
    #rConstVal{type = ?INT, val = LeftVal},
    #rConstVal{type = ?INT, val = RightVal})
    when is_integer(LeftVal) andalso is_integer(RightVal) ->
    #rConstVal{type = ?INT, val = LeftVal * RightVal};
apply_operator('/',
    #rConstVal{type = ?INT, val = LeftVal},
    #rConstVal{type = ?INT, val = RightVal})
    when is_integer(LeftVal) andalso is_integer(RightVal) ->
    #rConstVal{type = ?INT, val = LeftVal div RightVal};
apply_operator('<<',
    #rConstVal{type = ?INT, val = LeftVal},
    #rConstVal{type = ?INT, val = RightVal})
    when is_integer(LeftVal) andalso is_integer(RightVal) ->
    #rConstVal{type = ?INT, val = LeftVal bsl RightVal};
apply_operator('>>',
    #rConstVal{type = ?INT, val = LeftVal},
    #rConstVal{type = ?INT, val = RightVal})
    when is_integer(LeftVal) andalso is_integer(RightVal) ->
    #rConstVal{type = ?INT, val = LeftVal bsr RightVal};
apply_operator('<',
    #rConstVal{type = ?INT, val = LeftVal},
    #rConstVal{type = ?INT, val = RightVal})
    when is_integer(LeftVal) andalso is_integer(RightVal) ->
    #rConstVal{type = ?BOOL, val = LeftVal < RightVal};
apply_operator('<=',
    #rConstVal{type = ?INT, val = LeftVal},
    #rConstVal{type = ?INT, val = RightVal})
    when is_integer(LeftVal) andalso is_integer(RightVal) ->
    #rConstVal{type = ?BOOL, val = LeftVal =< RightVal};
apply_operator('>',
    #rConstVal{type = ?INT, val = LeftVal},
    #rConstVal{type = ?INT, val = RightVal})
    when is_integer(LeftVal) andalso is_integer(RightVal) ->
    #rConstVal{type = ?BOOL, val = LeftVal > RightVal};
apply_operator('>=',
    #rConstVal{type = ?INT, val = LeftVal},
    #rConstVal{type = ?INT, val = RightVal})
    when is_integer(LeftVal) andalso is_integer(RightVal) ->
    #rConstVal{type = ?BOOL, val = LeftVal >= RightVal};
apply_operator('==',
    #rConstVal{type = ?INT, val = LeftVal},
    #rConstVal{type = ?INT, val = RightVal})
    when is_integer(LeftVal) andalso is_integer(RightVal) ->
    #rConstVal{type = ?BOOL, val = LeftVal==RightVal};
apply_operator('==',
    #rConstVal{type = ?BOOL, val = LeftVal},
    #rConstVal{type = ?BOOL, val = RightVal})
    when is_boolean(LeftVal) andalso is_boolean(RightVal) ->
    #rConstVal{type = ?BOOL, val = LeftVal==RightVal};
apply_operator('&&',
    #rConstVal{type = ?BOOL, val = LeftVal},
    #rConstVal{type = ?BOOL, val = RightVal})
    when is_boolean(LeftVal) andalso is_boolean(RightVal) ->
    #rConstVal{type = ?BOOL, val = LeftVal andalso RightVal};
apply_operator('||',
    #rConstVal{type = ?BOOL, val = LeftVal},
    #rConstVal{type = ?BOOL, val = RightVal})
    when is_boolean(LeftVal) andalso is_boolean(RightVal) ->
    #rConstVal{type = ?BOOL, val = LeftVal orelse RightVal};
apply_operator(UnknownOperator,
    #rConstVal{type = LeftType, val = LeftVal},
    #rConstVal{type = RightType, val = RightVal}) ->
    throw({cannot_apply_operator_for_args, {operator, UnknownOperator},
        {left_arg, {type, LeftType}, {value, LeftVal}},
        {right_arg, {type, RightType}, {value, RightVal}}}).

apply_operator('-',
    #rConstVal{type = ?INT, val = Val})
    when is_integer(Val) ->
    #rConstVal{type = ?INT, val = -Val};
apply_operator('!',
    #rConstVal{type = ?BOOL, val = Val})
    when is_boolean(Val) ->
    #rConstVal{type = ?BOOL, val = not Val};
apply_operator(UnknownOperator,
    #rConstVal{type = ArgType, val = ArgVal}) ->
    throw({cannot_apply_operator_for_args, {operator, UnknownOperator},
        {arg, {type, ArgType}, {value, ArgVal}}}).



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%  internal functions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Processess a list of statements (which represent a code block). It's done in a way where
%  a single statement can stop the body's execution. The body's execution can be aborted
%  by statements such as "return", "break" or "continue".
process_code_block(St, #rBody{statements=[]}) ->
    logger:log("process code block: END", tag(St)),
    no_value;

process_code_block(St, #rBody{statements=Body}) when is_list(Body), is_record(St, pState) ->
    logger:log("process code block  ~150P", tag(St), [Body, 7]),
    StatementFollowUp = process_block_statement(St, hd(Body)),

    case StatementFollowUp of
        next_instruction ->
            logger:log("process code block => next instr", tag(St)),
            BodyTail = #rBody{statements = tl(Body)},
            process_code_block(St, BodyTail);
        ControlFlowAlteration ->
            logger:log("process code block => control flow change: ~150p", tag(St),
                [ControlFlowAlteration]),
            ControlFlowAlteration
    end.


process_block_statement(State, Statement) ->
    logger:log("process statement -- begin:  ~180P", tag(State), [Statement, 6]),
    Res = do_exec(State, Statement),
    logger:log("process statement -- end  ~180P", tag(State), [Statement, 6]),

    case Res of
        no_value ->
            next_instruction;
        {val, _Value} ->
            next_instruction;
        ControlFlowAlteration ->
            ControlFlowAlteration
    end.


exec_loop(St, {Label, CondExpr, Increment, Body}) when is_record(Body, rBody) ->
    % check loop condition; on success execute the body
    {val, Condition} = do_exec(St, CondExpr),
    logger:log("loop - condition => ~p", tag(St), [Condition#rConstVal.val]),
    Scope = St#pState.scope,
    wait_for_clock(St),

    case Condition of
        ?FALSE ->
            IterationOutcome = condition_failed;
        ?TRUE ->
            IterationBarrier = request_barrier(St),
            % TODO: is this barrier really needed?

            % execute the body
            scope:open_frame(Scope),
            IterationOutcome = process_code_block(St, Body),
            scope:close_frame(Scope),

            logger:log("loop - finished iteration body", tag(St)),
            sync_on_barrier(St, IterationBarrier)
    end,

    % decide the course of action: continue looping or return control level up
    case IterationOutcome of
        {return, RetValOrNoVal} ->
            logger:log("loop, iteration => return,  ret val: ~p", tag(St), [RetValOrNoVal]),
            {return, RetValOrNoVal};
        no_value ->
            logger:log("loop, iteration => done, carry on", tag(St)),
            do_exec(St, Increment),
            exec_loop(St, {Label, CondExpr, Increment, Body});
        {continue, L}
            when L==no_label orelse L==Label ->
            logger:log("loop, iteration => continue  current loop", tag(St)),
            do_exec(St, Increment),
            exec_loop(St, {Label, CondExpr, Increment, Body});
        {continue, OuterLabel} ->
            logger:log("loop, iteration => continue  outer loop", tag(St)),
            {continue, OuterLabel};
        {break, L}
            when L==no_label orelse L==Label ->
            logger:log("loop, iteration => break  current loop", tag(St)),
            no_value;
        {break, OuterLabel} ->
            logger:log("loop, iteration => break  outer loop", tag(St)),
            {break, OuterLabel};
        condition_failed ->
            logger:log("loop, iteration => cond false", tag(St)),
            no_value
    end.


make_loop_args(FL) when is_record(FL, rForLoop) ->
    {
        FL#rForLoop.label,
        FL#rForLoop.'cond',
        FL#rForLoop.increment,
        FL#rForLoop.body
    };
make_loop_args(WL) when is_record(WL, rWhileLoop) ->
    {
        WL#rWhileLoop.label,
        WL#rWhileLoop.'cond',
        ?NULL_INCREMENT,
        WL#rWhileLoop.body
    }.


cartesian_product([ParArg]) ->
    #rParallelArg{ident = VarName, range = #rRange{'begin' = B, 'end' = E}} = ParArg,
    Begin = B#rConstVal.val,
    End = E#rConstVal.val,
    [ [{VarName, Num}] || Num <- lists:seq(Begin, End) ];
cartesian_product(ParArgs) when is_list(ParArgs) ->
    #rParallelArg{ident = VarName, range = #rRange{'begin' = B, 'end' = E}} = hd(ParArgs),
    PartialRes = cartesian_product(tl(ParArgs)),
    Begin = B#rConstVal.val,
    End = E#rConstVal.val,
    [ [{VarName, Num} | Part] || Num <- lists:seq(Begin, End), Part <- PartialRes ].


compute_subname(BaseName, ParArgsCombination) ->
    ParArgsValues = [ ParArgValue || {_ParArgName, ParArgValue} <- ParArgsCombination ],
    lists:foldl(
        fun(Val, Name) ->
            lists:concat([Name, ",", Val])
        end,
        BaseName,
        ParArgsValues).


fill_scope_with_parargs(Scope, [{ArgName, ArgVal} | ArgsTail]) ->
    Addr = util:dereference(#rSimpleVariable{name = ArgName}),
    scope:add_var(Scope, Addr, ?INT, [const]),
    scope:write_var(Scope, Addr, ArgVal),

    fill_scope_with_parargs(Scope, ArgsTail);

fill_scope_with_parargs(_Scope, []) ->
    ok.


eval(State, Arg) ->
    % ensure that a value is returned
    {val, Value} = do_exec(State, Arg),
    Value.


eval_indices(State, #rArrayElement{var = Var, index = Index}) ->
    #rArrayElement{
        var = eval_indices(State, Var),
        index = eval(State, Index)};
eval_indices(_State, SimpleVariable) when is_record(SimpleVariable, rSimpleVariable) ->
    SimpleVariable.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%  helpers of lesser importance
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

wait_for_clock(#pState{manager = no_manager}) ->
    % during pre-execution phase there is no need for a manager
    ok;
wait_for_clock(St=#pState{manager = Manager}) when is_pid(Manager) ->
    logger:log(" clock sync", tag(St)),
    ok = manager:sync_on_tick(Manager),
    ok.


request_barrier(St=#pState{manager = Manager}) when is_pid(Manager) ->
    logger:log(" request barrier", tag(St)),
    {ok, Barrier} = manager:request_barrier(Manager),
    Barrier.


sync_on_barrier(St=#pState{manager = Manager}, Barrier) when is_pid(Manager) ->
    logger:log(" sync on barrier", tag(St)),
    ok = manager:sync_on_barrier(Manager, Barrier).


tag(St) when is_record(St, pState) ->
    {?MODULE, St#pState.name}.


create_processor(Supervisor, Name, Scope, Manager, Memory) ->
    ProcessorChildSpec = {
        _Id = process_id(processor, Name),
        {processor, start_link, _Args=[Supervisor]},
        ?WORKER_RESTART_STRATEGY,
        ?WORKER_SHUTDOWN_TIMEOUT,
        worker,
        [processor, ?PROCESSOR_IMPL_MODULE]
    },
    {ok, Processor} = supervisor:start_child(Supervisor, ProcessorChildSpec),

    prepare(Processor, Name, Scope, Manager, Memory),
    Processor.


create_cloned_scope(Supervisor, Name, ScopeToClone) ->
    ScopeChildSpec = {
        _Id = process_id(scope, Name),
        {scope, start_link, _Args=[ScopeToClone]},
        ?WORKER_RESTART_STRATEGY,
        ?WORKER_SHUTDOWN_TIMEOUT,
        worker,
        [scope, ?SCOPE_IMPL_MODULE]
    },
    {ok, Scope} = supervisor:start_child(Supervisor, ScopeChildSpec),

    % this frame is never closed but the processor finishes before it would close, anyway
    scope:open_frame(Scope),
    Scope.


destroy_scope(Supervisor, Name) ->
    ScopeId = process_id(scope, Name),

    supervisor:terminate_child(Supervisor, ScopeId),
    supervisor:delete_child(Supervisor, ScopeId).


process_id(processor, Name) ->
    {processor, Name};

process_id(scope, Name) ->
    {scope, Name}.


wait_for_processors_to_terminate([]) ->
    ok;

wait_for_processors_to_terminate([Processor | PTail]) when is_pid(Processor) ->
    Ref = erlang:monitor(process, Processor),
    receive
        {'DOWN', Ref, process, Processor, _} -> ok
    end,
    wait_for_processors_to_terminate(PTail).



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%  gen fsm callbacks
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

init({supervisor, Supervisor}) ->
    {ok, awaiting_preparation, _State={sup, Supervisor}}.


terminate(normal, _GenFsmState, St) ->
    logger:log("(~p) terminated (normal)", tag(St), [self()]),
    destroy_scope(St#pState.supervisor, St#pState.name);

terminate(shutdown, _GenFsmState, St) ->
    logger:log("(~p) terminated by supervisor (shutdown)", tag(St), [self()]);

terminate({shutdown, Reason}, _GenFsmState, St) ->
    logger:log("(~p) terminated by own will, reason: ~p", tag(St), [self(), Reason]),
    destroy_scope(St#pState.supervisor, St#pState.name);

terminate({{bad_return_value, Tuple}, _}, _GenFsmState, St) when element(1,Tuple)==memory_model_violation ->
    % manager will report memory model violation so there's no need to log it here
    ok;

terminate(Other, _GenFsmState, St) ->
    logger:log("(~p) terminated because of unknown reason:~n ~p~n", tag(St), [self(), {aaa, Other}]).


handle_event(_Event, _GenFsmState, _St) ->
    erlang:error(not_supported).


handle_sync_event(_Event=stop, _From, _GenFsmState, St) ->
    {stop, _Reason={shutdown, user_called_stop}, _Reply=ok, St};

handle_sync_event(Event, _From, _GenFsmState, St) ->
    logger:log("unrecognised event: ~p", tag(St), [Event]),
    {stop, _Reason={unknown_event, Event}, _Reply=ok, St}.


handle_info(Info, _GenFsmState, St) ->
    logger:log("unrecognized message: ~p", tag(St), [Info]),
    erlang:error(not_supported).


code_change(_OldVsn, _GenFsmState, _St, _Extra) ->
    erlang:error(not_implemented).
