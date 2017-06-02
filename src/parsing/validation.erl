%%%-------------------------------------------------------------------
%%% @author Gabriel Fortin
%%% @copyright (C) 2015, Gabriel Fortin
%%% @doc
%%%
%%% @end
%%% Created : 21. Oct 2015 8:16 PM
%%%-------------------------------------------------------------------
-module(validation).
-author("Gabriel Fortin").

-include("../common/ast.hrl").

%% API
-export([program_ast/1]).

-define(ALPHA, "_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ").
-define(ALPHA_NUM, "_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789").

-record(not_an_instance_of, {
    id,
    'ARG',
    'STACK'
}).

% TODO: an input var declaration shouldn't have an initialisation (VD#rVarDecl.val == empty)


%% ===================================================================
%% API
%% ===================================================================

program_ast(Ast) ->
    try validate_tProgram(Ast, []) of
        _ ->
            ok
    catch
        throw:Failure ->
            {validation_failure, Failure}
    end.


%% ===================================================================
%% Private functions
%% ===================================================================

validate_tProgram(X, Stack) -> validate_rProgram(X, Stack).
validate_rProgram(X, Stack) when is_record(X, rProgram) ->
    logger:log_enter("rProgram", ?MODULE),
    Push = fun(I) -> [{rProgram, I} | Stack] end,
    validate_all_of(X#rProgram.sttmnts, fun validate_tGlobalStatement/2, Push(sttmnts)),
    logger:log_exit(?MODULE);
validate_rProgram(X, Stack) ->
    fail(rProgram, X, Stack).

validate_tGlobalStatement(X, Stack) ->
    logger:log("tGlobalStatement  ~120P", ?MODULE, [X, 2]),
    Stack_1 = [{alternative, tGlobalStatement} | Stack],
    validate_one(X, [
            fun validate_tVarDecl/2,
            fun validate_tVarLoad/2,
            fun validate_tFunctionDef/2],
            Stack_1).

validate_tFunctionDef(X, Stack) -> validate_rFunctionDef(X, Stack).
validate_rFunctionDef(X, Stack) when is_record(X, rFunctionDef) ->
    logger:log_enter("rFunctionDef", ?MODULE),
    Push = fun(I) -> [{rFunctionDef, I} | Stack] end,
    validate_tIdentifier(X#rFunctionDef.ident, Push(ident)),
    validate_all_of(X#rFunctionDef.args, fun validate_tVarDecl/2, Push(args)),
    validate_tFunRetType(X#rFunctionDef.retType, Push(retType)),
    validate_tBody(X#rFunctionDef.body, Push(body)),
    logger:log_exit(?MODULE);
validate_rFunctionDef(X, Stack) ->
    fail(rFunctionDef, X, Stack).

validate_tVarLoad(X, Stack) -> validate_rVarLoad(X, Stack).
validate_rVarLoad(X, Stack) when is_record(X, rVarLoad) ->
    logger:log_enter("rVarLoad", ?MODULE),
    Push = fun(I) -> [{rVarLoad, I} | Stack] end,
    validate_tIdentifier(X#rVarLoad.ident, Push(ident)),
    logger:log_exit(?MODULE);
validate_rVarLoad(X, Stack) ->
    fail(rVarLoad, X, Stack).

%%  VARIABLES' USE  %%
validate_tVariable(X, Stack) ->
    logger:log("tVariable  ~120P", ?MODULE, [X, 2]),
    Stack_1 = [{alternative, tVariable} | Stack],
    validate_one(X, [
            fun validate_tSimpleVariable/2,
            fun validate_tArrayElement/2 ],
            Stack_1).

validate_tSimpleVariable(X, Stack) -> validate_rSimpleVariable(X, Stack).
validate_rSimpleVariable(X, Stack) when is_record(X, rSimpleVariable) ->
    logger:log_enter("rSimpleVariable", ?MODULE),
    Push = fun(I) -> [{rSimpleVariable, I} | Stack] end,
    validate_tIdentifier(X#rSimpleVariable.name, Push(name)),
    logger:log_exit(?MODULE);
validate_rSimpleVariable(X, Stack) ->
    fail(rSimpleVariable, X, Stack).

validate_tArrayElement(X, Stack) -> validate_rArrayElement(X, Stack).
validate_rArrayElement(X, Stack) when is_record(X, rArrayElement) ->
    logger:log_enter("rArrayElement", ?MODULE),
    Push = fun(I) -> [{rArrayElement, I} | Stack] end,
    validate_tVariable(X#rArrayElement.var, Push(var)),
    validate_tExpression(X#rArrayElement.index, Push(index)),
    logger:log_exit(?MODULE);
validate_rArrayElement(X, Stack) ->
    fail(rArrayElement, X, Stack).

%%  EXPRESSIONS  %%
validate_tExpression(X, Stack) ->
    logger:log("tExpression  ~120P", ?MODULE, [X, 2]),
    Stack_1 = [{alternative, tExpression} | Stack],
    validate_one(X, [
            fun validate_tConstVal/2,
            fun validate_tVariable/2,
            fun validate_tFunctionCall/2,
            fun validate_tAssignment/2,
            fun validate_tBinaryExpr/2,
            fun validate_tUnaryExpr/2 ],
            Stack_1).

validate_tBinaryExpr(X, Stack) -> validate_rBinaryExpr(X, Stack).
validate_rBinaryExpr(X, Stack) when is_record(X, rBinaryExpr) ->
    logger:log_enter("rBinaryExpr", ?MODULE),
    Push = fun(I) -> [{rBinaryExpr, I} | Stack] end,
    validate_tBinaryOp(X#rBinaryExpr.op, Push(op)),
    validate_tExpression(X#rBinaryExpr.left, Push(left)),
    validate_tExpression(X#rBinaryExpr.right, Push(right)),
    logger:log_exit(?MODULE);
validate_rBinaryExpr(X, Stack) ->
    fail(rBinaryExpr, X, Stack).

validate_tUnaryExpr(X, Stack) -> validate_rUnaryExpr(X, Stack).
validate_rUnaryExpr(X, Stack) when is_record(X, rUnaryExpr) ->
    logger:log_enter("rUnaryExpr", ?MODULE),
    Push = fun(I) -> [{rUnaryExpr, I} | Stack] end,
    validate_tUnaryOp(X#rUnaryExpr.op, Push(op)),
    validate_tExpression(X#rUnaryExpr.arg, Push(arg)),
    logger:log_exit(?MODULE);
validate_rUnaryExpr(X, Stack) ->
    fail(rUnaryExpr, X, Stack).

validate_tBinaryOp(X, Stack) ->
    logger:log("binary_op", ?MODULE),
    OpIsCorrect = lists:member(X, ['+', '-', '*', '/', '<<', '>>',
            '&&', '||', '<', '<=', '>', '>=', '==']),
    case OpIsCorrect of
        true -> true;
        false -> fail(binary_op, X, Stack)
    end.

validate_tUnaryOp(X, Stack) ->
    logger:log("unary_op", ?MODULE),
    OpIsCorrect = lists:member(X, ['-', '++', '--', '!']),
    case OpIsCorrect of
        true -> true;
        false -> fail(unary_op, X, Stack)
    end.

%%  STATEMENTS  %%
validate_tStatement(X, Stack) ->
    logger:log("tStatement  ~120P", ?MODULE, [X, 2]),
    Stack_1 = [{alternative, tStatement} | Stack],
    validate_one(X, [
            fun validate_tExpression/2,
            fun validate_tVarDecl/2,
            fun validate_tParallelBlock/2,
            fun validate_tIfInstr/2,
            fun validate_tWhileLoop/2,
            fun validate_tForLoop/2,
            fun validate_tLoopControl/2,
            fun validate_tReturnInstr/2 ],
            Stack_1).

validate_tFunctionCall(X, Stack) -> validate_rFunctionCall(X, Stack).
validate_rFunctionCall(X, Stack) when is_record(X, rFunctionCall) ->
    logger:log_enter("rFunctionCall", ?MODULE),
    Push = fun(I) -> [{rFunctionCall, I} | Stack] end,
    validate_tIdentifier(X#rFunctionCall.name, Push(name)),
    validate_all_of(X#rFunctionCall.args, fun validate_tExpression/2, Push(args)),
    logger:log_exit(?MODULE);
validate_rFunctionCall(X, Stack) ->
    fail(rFunctionCall, X, Stack).

validate_tAssignment(X, Stack) -> validate_rAssignment(X, Stack).
validate_rAssignment(X, Stack) when is_record(X, rAssignment) ->
    logger:log_enter("rAssignment", ?MODULE),
    Push = fun(I) -> [{rAssignment, I} | Stack] end,
    validate_tVariable(X#rAssignment.var, Push(var)),
    validate_tExpression(X#rAssignment.val, Push(val)),
    logger:log_exit(?MODULE);
validate_rAssignment(X, Stack) ->
    fail(rAssignment, X, Stack).

validate_tParallelBlock(X, Stack) -> validate_rParallelBlock(X, Stack).
validate_rParallelBlock(X, Stack) when is_record(X, rParallelBlock) ->
    logger:log_enter("rParallelBlock", ?MODULE),
    Push = fun(I) -> [{rParallelBlock, I} | Stack] end,
    validate_all_of(X#rParallelBlock.args, fun validate_tParallelArg/2, Push(args)),
    validate_tBody(X#rParallelBlock.body, Push(body)),
    logger:log_exit(?MODULE);
validate_rParallelBlock(X, Stack) ->
    fail(rParallelBlock, X, Stack).

validate_tParallelArg(X, Stack) -> validate_rParallelArg(X, Stack).
validate_rParallelArg(X, Stack) when is_record(X, rParallelArg) ->
    logger:log_enter("rParallelArg", ?MODULE),
    Push = fun(I) -> [{rParallelArg, I} | Stack] end,
    validate_tIdentifier(X#rParallelArg.ident, Push(ident)),
    validate_tRange(X#rParallelArg.range, Push(range)),
    logger:log_exit(?MODULE);
validate_rParallelArg(X, Stack) ->
    fail(rParallelArg, X, Stack).

validate_tIfInstr(X, Stack) -> validate_rIfInstr(X, Stack).
validate_rIfInstr(X, Stack) when is_record(X, rIfInstr) ->
    logger:log_enter("rIfInstr", ?MODULE),
    Push = fun(I) -> [{rIfInstr, I} | Stack] end,
    validate_tExpression(X#rIfInstr.'cond', Push('cond')),
    validate_tBody(X#rIfInstr.then, Push(then)),
    validate_tBody(X#rIfInstr.else, Push(else)),
    logger:log_exit(?MODULE);
validate_rIfInstr(X, Stack) ->
    fail(rIfInstr, X, Stack).

validate_tWhileLoop(X, Stack) -> validate_rWhileLoop(X, Stack).
validate_rWhileLoop(X, Stack) when is_record(X, rWhileLoop) ->
    logger:log_enter("rWhileLoop", ?MODULE),
    Push = fun(I) -> [{rWhileLoop, I} | Stack] end,
    (
        X#rWhileLoop.label == no_label
            orelse
        validate_string_type(X#rWhileLoop.label, Push(label))
    ),
    validate_tExpression(X#rWhileLoop.'cond', Push('cond')),
    validate_tBody(X#rWhileLoop.body, Push(body)),
    logger:log_exit(?MODULE);
validate_rWhileLoop(X, Stack) ->
    fail(rWhileLoop, X, Stack).

validate_tForLoop(X, Stack) -> validate_rForLoop(X, Stack).
validate_rForLoop(X, Stack) when is_record(X, rForLoop) ->
    logger:log_enter("rForLoop", ?MODULE),
    Push = fun(I) -> [{rForLoop, I} | Stack] end,
    (
        X#rForLoop.label == no_label
            orelse
        validate_string_type(X#rForLoop.label, Push(label))
    ),
    validate_tVarDecl(X#rForLoop.varInit, Push(varInit)),
    validate_tExpression(X#rForLoop.'cond', Push('cond')),
    validate_tExpression(X#rForLoop.increment, Push('cond')),
    validate_tBody(X#rForLoop.body, Push(body)),
    logger:log_exit(?MODULE);
validate_rForLoop(X, Stack) ->
    fail(rForLoop, X, Stack).

validate_tVarDecl(X, Stack) -> validate_rVarDecl(X, Stack).
validate_rVarDecl(X, Stack) when is_record(X, rVarDecl) ->
    logger:log_enter("rVarDecl", ?MODULE),
    Push = fun(I) -> [{rVarDecl, I} | Stack] end,
    validate_tVarType(X#rVarDecl.type, Push(type)),
    validate_tIdentifier(X#rVarDecl.ident, Push(ident)),
    (
        X#rVarDecl.val == empty
            orelse
        validate_tExpression(X#rVarDecl.val, Push(val))
    ),
    case is_boolean(X#rVarDecl.isConst) of
        true -> true;
        false -> fail(isConst, X, Stack)
    end,
    case is_boolean(X#rVarDecl.isGlobal) of
        true -> true;
        false -> fail(isGlobal, X, Stack)
    end,
    case is_boolean(X#rVarDecl.isInputVar) of
        true -> true;
        false -> fail(isInputVar, X, Stack)
    end,
    case is_boolean(X#rVarDecl.isOutputVar) of
        true -> true;
        false -> fail(isOutputVar, X, Stack)
    end,
    logger:log_exit(?MODULE);
validate_rVarDecl(X, Stack) ->
    fail(rVarDecl, X, Stack).

validate_tLoopControl(X, Stack) -> validate_rLoopControl(X, Stack).
validate_rLoopControl(X, Stack) when is_record(X, rLoopControl) ->
    logger:log_enter("rLoopControl", ?MODULE),
    Push = fun(I) -> [{rLoopControl, I} | Stack] end,
    (
        X#rLoopControl.label == no_label
            orelse
        validate_string_type(X#rLoopControl.label, Push(label))
    ),
    lists:member(X#rLoopControl.instr, [break, continue]),
    logger:log_exit(?MODULE);
validate_rLoopControl(X, Stack) ->
    fail(rLoopControl, X, Stack).

validate_tReturnInstr(X, Stack) -> validate_rReturnInstr(X, Stack).
validate_rReturnInstr(X, Stack) when is_record(X, rReturnInstr) ->
    logger:log_enter("rReturnInstr", ?MODULE),
    Push = fun(I) -> [{rReturnInstr, I} | Stack] end,
    (
        X#rReturnInstr.val == empty
            orelse
        validate_tExpression(X#rReturnInstr.val, Push(val))
    ),
    logger:log_exit(?MODULE);
validate_rReturnInstr(X, Stack) ->
    fail(rReturnInstr, X, Stack).

%%  TYPES  %%
validate_tVarType(X, Stack) ->
    logger:log("tVarType  ~120P", ?MODULE, [X, 2]),
    Stack_1 = [{alternative, tVarType} | Stack],
    validate_one(X, [
            fun validate_tSimpleVarType/2,
            fun validate_tArrayVarType/2 ],
            Stack_1).

validate_tSimpleVarType(X, Stack) -> validate_rSimpleVarType(X, Stack).
validate_rSimpleVarType(X, Stack) when is_record(X, rSimpleVarType) ->
    logger:log("rSimpleVarType", ?MODULE),
    IsTypenameCorrect = lists:member(X#rSimpleVarType.typeName, [int, bool]),
    case IsTypenameCorrect of
        true -> true;
        false -> fail(rSimpleVarType, X, Stack)
    end;
validate_rSimpleVarType(X, Stack) ->
    fail(rSimpleVarType, X, Stack).

validate_tArrayVarType(X, Stack) -> validate_rArrayVarType(X, Stack).
validate_rArrayVarType(X, Stack) when is_record(X, rArrayVarType) ->
    logger:log_enter("rArrayVarType", ?MODULE),
    Push = fun(I) -> [{rArrayVarType, I} | Stack] end,
    validate_tRange(X#rArrayVarType.range, Push(range)),
    validate_tVarType(X#rArrayVarType.baseType, Push(baseType)),
    logger:log_exit(?MODULE);
validate_rArrayVarType(X, Stack) ->
    fail(rArrayVarType, X, Stack).

validate_tFunRetType(X, Stack) ->
    X == 'void'
        orelse
    validate_tVarType(X, Stack).

%%  COMMON  %%
validate_tRange(X, Stack) -> validate_rRange(X, Stack).
validate_rRange(X, Stack) when is_record(X, rRange) ->
    logger:log_enter("rRange", ?MODULE),
    Push = fun(I) -> [{rRange, I} | Stack] end,
    validate_tExpression(X#rRange.'begin', Push('begin')),
    validate_tExpression(X#rRange.'end', Push('end')),
    logger:log_exit(?MODULE);
validate_rRange(X, Stack) ->
    fail(rRange, X, Stack).

validate_tIdentifier(X, Stack) ->
    validate_string_type(X, Stack).

validate_tConstVal(X, Stack) -> validate_rConstVal(X, Stack).
validate_rConstVal(X, Stack) when is_record(X, rConstVal) ->
    logger:log_enter("rConstVal", ?MODULE),
    Push = fun(I) -> [{rConstVal, I} | Stack] end,
    validate_tVarType(X#rConstVal.type, Push(type)),
    % X#rConstVal.val -- not validating as it is allowed to by anything
    logger:log_exit(?MODULE);
validate_rConstVal(X, Stack) ->
    fail(rConstVal, X, Stack).

validate_tBody(X, Stack) -> validate_rBody(X, Stack).
validate_rBody(X, Stack) when is_record(X, rBody) ->
    logger:log_enter("rBody", ?MODULE),
    Push = fun(I) -> [{rBody, I} | Stack] end,
    validate_all_of(X#rBody.statements, fun validate_tStatement/2, Push(statements)),
    logger:log_exit(?MODULE);
validate_rBody(X, Stack) ->
    fail(rBody, X, Stack).

validate_string_type(X, Stack) when is_list(X) ->
    logger:log("validate_string_type:  ~p", ?MODULE, [X]),
    StringIsCorrect = lists:member(hd(X), ?ALPHA) andalso
            lists:all(fun(Char) -> lists:member(Char, ?ALPHA_NUM) end, tl(X)),
    case StringIsCorrect of
        true -> true;
        false -> fail(tIdentifier, X, Stack)
    end.



%% ===================================================================
%% Helper functions
%% ===================================================================

% unified internal behaviour on validation failure
% IMPORTANT: this function must be kept in sync with 'validate_one_/5' function
fail(NodeName, Arg, Stack) ->
    throw(#not_an_instance_of{
        id = NodeName,
        'ARG' = Arg,
        'STACK' = Stack
    }).


validate_all_of(Args, Fun, Stack) ->
    all_of_(Args, Fun, Stack, 0).

all_of_([Arg | ArgTail], Fun, Stack, Idx) ->
    logger:log("item ~p of ~p", ?MODULE, [Idx, hd(Stack)]),
    Stack_1 = [{index, Idx} | Stack],
    Fun(Arg, Stack_1),
    all_of_(ArgTail, Fun, Stack, Idx+1);
all_of_([], _F, _S, _I) ->
    true.


validate_one('##getting fun name#', _, Stack) ->  % needed for 'extract_id_of_validation_function/1'
    [{alternative, Name} | _] = Stack,
    fail(Name, '##getting fun name#', no_failure_yet);
validate_one(Arg, Funs, Stack) when is_list(Stack) ->
    logger:log_enter("validate one, when arg is ~120P", ?MODULE, [Arg, 4]),
    % extract fun names
    FunsNames = [ extract_id_of_validation_function(Fun) || Fun <- Funs ],
    Stack_1 = [{validate_one, FunsNames} | Stack],
    PotentialFailure = #not_an_instance_of{'STACK' = no_failure_yet},
    try validate_one_(Arg, Funs, Stack_1, FunsNames, PotentialFailure) of
        _ ->
            logger:log_exit(?MODULE)
    catch
        throw:X ->
            logger:log_exit(?MODULE),
            throw(X)
    end.

validate_one_(Arg, [Fun | FunTail], Stack, FunsNames, PotentialFailure)
        when is_function(Fun, 2), is_list(Stack), is_record(PotentialFailure, not_an_instance_of) ->
    FunName = extract_id_of_validation_function(Fun),
    % try to validate 'Arg' with 'Fun'
    try Fun(Arg, Stack) of
        Res ->
            % validation with 'Fun' successful, return
            logger:log("<<  val one  success!  chose ~p as ~120p", ?MODULE,
                    [FunName, element(2, lists:nth(2, Stack))]),
            Res
    catch
        throw:#not_an_instance_of{'STACK' = Stack} ->
            % validation failed immediately (hence, the stack is unchanged) while calling 'Fun', so
            % the type of 'Arg' is rejected explicitely by 'Fun' -- a "shallow failure"
            logger:log("<< val one  (shallow) failure for ~P as ~p", ?MODULE, [Arg, 2, FunName]),
            validate_one_(Arg, FunTail, Stack, FunsNames, PotentialFailure);
        throw:DeeperFailure when is_record(DeeperFailure, not_an_instance_of) ->
            % probably found the 'Fun' that would accept 'Arg' but a deeper validation failed
            % saving the deeper failure to return it in case the whole alternative fails
            logger:log("<< val one  (deep) failure for:  ~P as ~p", ?MODULE, [Arg, 2, FunName]),
            validate_one_(Arg, FunTail, Stack, FunsNames, DeeperFailure)
    end;
validate_one_(Arg, [], Stack, FunsNames, PotentialFailure)
        when no_failure_yet == PotentialFailure#not_an_instance_of.'STACK' ->
    logger:log("<<<val one  NONE MATCHED, shallow failure", ?MODULE),
    fail({alternative, FunsNames}, Arg, Stack);
validate_one_(_A, [], _S, _FN, Failure) when is_record(Failure, not_an_instance_of) ->
    logger:log("<<<val one  NONE MATCHED, deep failure", ?MODULE),
    throw(Failure).

extract_id_of_validation_function(Fun) ->
    Tag = ?MODULE,
    % save current setting
    {ok, TagList} = logger:filter_set([]),
    {ok, Mode} = logger:get_filter_mode(),
    TempTagList = case {Mode, lists:member(Tag, TagList)} of
        {exclude, true} ->
            TagList;
        {include, false} ->
            TagList;
        {exclude, false} ->
            [Tag | TagList];
        {inclue, true} ->
            [Tag | TagList]
    end,
    % first, disable logging
    logger:filter_set(TempTagList),
    % then, proper extraction logic
    Res = try Fun('##getting fun name#', []) catch
        throw:#not_an_instance_of{id = Id} ->
            Id
    end,
    % finally, restore logging
    logger:filter_set(TagList),
    Res.

