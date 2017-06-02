%%%-------------------------------------------------------------------
%%% @author Gabriel Fortin
%%% @copyright (C) 2015, Gabriel Fortin
%%% @doc
%%% This header file contains types() and records for the() Abstract Syntax Tree.
%%% @end
%%% Created : 20. May 2015 7:46 PM
%%%-------------------------------------------------------------------
-author("Gabriel Fortin").

%% Remarks:
%%  — to grasp the AST structure in this file it's best to start by looking at types'
%%    definitions (starting around line 100)
%%  — the void type is allowed only as a function's return type
%%  — 'break' and break are the same in Erlang - they are atoms,
%%    the reason I use quotes is that I mean it to represent the literal string "break"
%%    in the code of the program


-export_type([tProgram/0]).

-define(INT, #rSimpleVarType{typeName = int}).
-define(BOOL, #rSimpleVarType{typeName = bool}).

-define(TRUE, #rConstVal{type = ?BOOL, val = true}).
-define(FALSE, #rConstVal{type = ?BOOL, val = false}).


%% DEFINITIONS OF RECORDS:

    %%  TOP LEVEL  %%
-record(rProgram, {
        sttmnts :: [tGlobalStatement()]  }).
-record(rFunctionDef, {
        ident   :: tIdentifier(),
        args    :: [tVarDecl()],
        retType :: tFunRetType(),
        body    :: tBody()  }).
-record(rVarLoad, {
        ident :: tIdentifier()  }).

    %%  VARIABLES' USE  %%
-record(rSimpleVariable, {
        name    :: tIdentifier()  }).
-record(rArrayElement, {
        var   :: tVariable(),
        index :: tExpression()  }).

    %%  EXPRESSIONS  %%
-record(rBinaryExpr, {
        op    :: tBinaryOp(),
        left  :: tExpression(),
        right :: tExpression()  }).
-record(rUnaryExpr, {
        op    :: tUnaryOp(),
        arg   :: tExpression()  }).

    %%  STATEMENTS  %%
-record(rFunctionCall, {
        name    :: tIdentifier(),
        args    :: [tExpression()]  }).
-record(rAssignment, {
        var     :: tVariable(),
        val     :: tExpression()  }).
-record(rParallelBlock, {
        args    :: [tParallelArg()],
        body    :: tBody()  }).
-record(rParallelArg, {
        ident   :: tIdentifier(),
        range   :: tRange()  }).
-record(rIfInstr, {
        'cond'  :: tExpression(),
        then    :: tBody(),
        else    :: tBody()  }).
-record(rWhileLoop, {
        label   :: no_label | string_type(),
        'cond'  :: tExpression(),
        body    :: tBody()  }).
-record(rForLoop, {
        label   :: no_label | string_type(),
        varInit :: tVarDecl(),
        'cond'  :: tExpression(),
        increment :: tExpression(),
        body    :: tBody()  }).
-record(rVarDecl, {
        type                :: tVarType(),
        ident               :: tIdentifier(),
        val                 :: empty | tExpression(),  % for global vars and fun args always empty
        isConst     = false :: boolean(),   % true also for "input" variables (but only non-arrays? or not?)
        isGlobal    = false :: boolean(),  % might be used to know when a var must be used in a special way
        isInputVar  = false :: boolean(),  % requires 'isGlobal'
        isOutputVar = false :: boolean()  }).  % requires 'isGlobal'
-record(rLoopControl, {
        label   :: no_label | string_type(),
        instr   :: 'break' | 'continue'  }).
-record(rReturnInstr, {
        val     :: empty | tExpression()  }).

    %%  TYPES  %%
-record(rSimpleVarType, {%simVarType, %% TODO: keep in sync with scope:varValue()
        typeName :: 'int' | 'bool'  }).  % | 'void'  }).  %% void? or better have the field blank?
                    %%  (I'm thinking about arrays of voids and how to avoid such things)
-record(rArrayVarType, {
        range    :: tRange(),
        baseType :: tVarType()  }).

    %%  COMMON  %%
-record(rRange, {
        'begin' :: tExpression(),
        'end'   :: tExpression()  }).
-record(rConstVal, {
        type    :: tVarType(),
        val     :: any()  }).
-record(rBody, {
        statements :: [tStatement()]  }).



%% DEFINITIONS OF TYPES:

    %%  TOP LEVEL  %%
-type tProgram()         :: #rProgram{}.
-type tGlobalStatement() :: tVarDecl() | tVarLoad() | tFunctionDef().
-type tFunctionDef()     :: #rFunctionDef{}.
-type tVarLoad()         :: #rVarLoad{}.

    %%  VARIABLES' USE  %%
-type tVariable()       :: tSimpleVariable() | tArrayElement().
-type tSimpleVariable() :: #rSimpleVariable{}.
-type tArrayElement()   :: #rArrayElement{}.

    %%  EXPRESSIONS  %%
-type tExpression() :: tConstVal() | tVariable() | tFunctionCall() |
                       tAssignment() | tBinaryExpr() | tUnaryExpr().
-type tBinaryExpr() :: #rBinaryExpr{}.
-type tUnaryExpr()  :: #rUnaryExpr{}.
-type tBinaryOp()   :: '+' | '-' | '*' | '/' | '<<' | '>>' |
                       '&&' | '||' | '<' | '<=' | '>' | '>=' | '=='.
-type tUnaryOp()    :: '-' | '++' | '--' | '!'.

    %%  STATEMENTS  %%
-type tStatement()     :: tExpression() | tVarDecl() | tParallelBlock() | tIfInstr() |
                          tWhileLoop() | tForLoop() | tLoopControl() | tReturnInstr().
-type tFunctionCall()  :: #rFunctionCall{}.
-type tAssignment()    :: #rAssignment{}.
-type tParallelBlock() :: #rParallelBlock{}.
-type tParallelArg()   :: #rParallelArg{}.
-type tIfInstr()       :: #rIfInstr{}.
-type tWhileLoop()     :: #rWhileLoop{}.
-type tForLoop()       :: #rForLoop{}.
-type tVarDecl()       :: #rVarDecl{}.
-type tLoopControl()   :: #rLoopControl{}.
-type tReturnInstr()   :: #rReturnInstr{}.

    %%  TYPES  %%
-type tVarType()       :: tSimpleVarType() | tArrayVarType().
-type tSimpleVarType() :: #rSimpleVarType{}.
-type tArrayVarType()  :: #rArrayVarType{}.
-type tFunRetType()    :: 'void' | tVarType().  %% TODO? move void into tVarType?

    %%  COMMON  %%
-type tRange()      :: #rRange{}.
-type tIdentifier() :: string_type().
-type tConstVal()   :: #rConstVal{}.
-type tBody()       :: #rBody{}.
%% -type string_type() :: bitstring().  % use binary strings for improved performance
-type string_type() :: string().  % use regular strings for debug and ease of use
        % TODO: keep in sync with functions in the 'util' module
