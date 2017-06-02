
%% Header "TODO header".

%%% Some formatting/syntax in this file is arbitrary.
%%% First must be said that the lhs of a rule is always an atom and so are all elements
%%% of the rhs of a rule.
%%% Symbols are sometimes surrounded by apostrophes. Some require it
%%% as not to be confused with elements of the file's syntax. Many, however,
%%% are deliberately surrounded by apostrophes to imply that they occur literally
%%% in the parsed program (keywords, non-alphabet characters).

%%% When a list of elements is expected, a non-terminal of the form "many_*s" is used.
%%% When such a list requires separators (like commas - when the number of separators is
%%% smaller by one than the number of elements), a non-terminal of the form "opt_*s" is used.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Nonterminals
    _program
    _global_statement
    _many_global_statements
    _var_load

    _var_decl
    _opt_var_decl_value
    _many_var_decl_modifiers
    _many_var_decl_ranges

    _variable
    _simple_variable
    _array_element

    _expression
    _const_val
    _e_bool_0  _e_bool_1
    _e_num_0  _e_num_1  _e_num_2
    _e_unary  _e_final
    _op_bool_0  _op_bool_1
    _op_num_0  _op_num_1  _op_num_2
    _op_unary

    _fun_call
    _fun_call_arg
    _many_fun_call_args
    _opt_fun_call_args

    _assignment
    _parallel_block
    _if_instr
    _while_loop _opt_label
    _for_loop
    _loop_control
    _return_instr

    _fun_def
    _fun_def_arg
    _many_fun_def_args
    _opt_fun_def_args

    _par_arg
    _opt_par_args

    _range

    _opt_else

    _type
    _array_type_range

    _body
    _statement
    _many_statements

    _user_symbol
    .




%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Terminals
    simple_type
    void
    user_symbol
    positive_integer
    boolean
    pardo
    load
    ';'
    ':'
    ','
    '['  ']'
    '('  ')'
    '{'  '}'
    '..'
    '='
    '<'  '>'  '<='  '>='  '=='  '!='
    '&&'  '||'
    '!'
    '+'  '-'  '*'  '/'  '<<'  '>>'
    var_modifier
    'if'  else
    while
    for
    loop_ctrl
    return
    .
%    '++'  '--'





%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Rootsymbol
    _program.


Endsymbol code_end_marker.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%% operator precedences


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%% grammar rules

%%%  PROGRAM  %%%
_program -> _many_global_statements
        : #rProgram{
            sttmnts = '$1'}.
_many_global_statements -> '$empty' : [].
_many_global_statements -> _global_statement  _many_global_statements
        : ['$1' | '$2'].
_global_statement -> _var_decl  ';'
        : format("gloabl _statement -> var_decl~n"),
        '$1'#rVarDecl{     % set the 'isGlobal' flag
            isGlobal = true}.
_global_statement -> _var_load  ';'  : '$1'.
_global_statement -> _fun_def  : '$1'.


%%%  FUNCTION DEF  %%%
_fun_def -> 'void'  _user_symbol  '('  _many_fun_def_args  ')'  '{'  _body  '}'
        : format("fun_def~n"),
        #rFunctionDef{
            retType = element(1, '$1'),
            ident = '$2',
            args = '$4',
            body = '$7'}.
_fun_def -> _type  _user_symbol  '('  _many_fun_def_args  ')'  '{'  _body  '}'
        : format("fun_def~n"),
        #rFunctionDef{
            retType = '$1',
            ident = '$2',
            args = '$4',
            body = '$7'}.
_many_fun_def_args -> '$empty' : [].
_many_fun_def_args -> _fun_def_arg  _opt_fun_def_args
        : ['$1' | '$2'].
_opt_fun_def_args -> '$empty' : [].
_opt_fun_def_args -> ','  _var_decl  _opt_fun_def_args
        : ['$2' | '$3'].
_fun_def_arg -> _var_decl
        : '$1'.


%%%  BODY  %%%
_body -> _many_statements
        : #rBody{
            statements = '$1'}.
_many_statements -> '$empty' : [].
_many_statements -> _statement  _many_statements
        : ['$1' | '$2'].


%%%  STATEMENT  %%%
_statement -> _expression    ';' : '$1'.
_statement -> _var_decl      ';' : '$1'.
_statement -> _parallel_block    : '$1'.
_statement -> _if_instr          : '$1'.
_statement -> _while_loop        : '$1'.
_statement -> _for_loop          : '$1'.
_statement -> _loop_control  ';' : '$1'.
_statement -> _return_instr  ';' : '$1'.


%%%  EXPRESSION  %%%
_expression -> _e_bool_0 : '$1'.
_expression -> _assignment : '$1'.

% boolean expressions
_e_bool_0 -> _e_bool_1 : '$1'.
_e_bool_0 -> _e_bool_1  _op_bool_0  _e_bool_0
        : #rBinaryExpr{
            op = '$2',
            left = '$1',
            right = '$3'}.
_e_bool_1 -> _e_num_0 : '$1'.
_e_bool_1 -> _e_num_0  _op_bool_1  _e_num_0
        : #rBinaryExpr{
            op = '$2',
            left = '$1',
            right = '$3'}.

% numerical expressions
_e_num_0 -> _e_num_1 : '$1'.
_e_num_0 -> _e_num_0  _op_num_0  _e_num_1
        : #rBinaryExpr{
            op = '$2',
            left = '$1',
            right = '$3'}.
_e_num_1 -> _e_num_2 : '$1'.
_e_num_1 -> _e_num_1  _op_num_1  _e_num_2
        : #rBinaryExpr{
            op = '$2',
            left = '$1',
            right = '$3'}.
_e_num_2 -> _e_unary : '$1'.
% bitshift operations are made non-commutative
_e_num_2 -> _e_unary  _op_num_2  _e_unary
        : #rBinaryExpr{
            op = '$2',
            left = '$1',
            right = '$3'}.
_e_unary -> _e_final : '$1'.
_e_unary -> _op_unary  _e_final
        : #rUnaryExpr{
            op = '$1',
            arg = '$2'}.
_e_final -> _const_val : '$1'.
_e_final -> _variable  : '$1'.
_e_final -> _fun_call  : '$1'.
_e_final -> '('  _expression  ')' : '$2'.

% boolean operators
_op_bool_0 -> '&&' : '&&'.
_op_bool_0 -> '||' : '||'.
_op_bool_1 -> '==' : '=='.
_op_bool_1 -> '!=' : '!='.
_op_bool_1 -> '<'  : '<'.
_op_bool_1 -> '>'  : '>'.
_op_bool_1 -> '<=' : '<='.
_op_bool_1 -> '>=' : '>='.

% numerical operators
_op_num_0 -> '+' : '+'.
_op_num_0 -> '-' : '-'.
_op_num_1 -> '*' : '*'.
_op_num_1 -> '/' : '/'.
_op_num_2 -> '<<' : '<<'.
_op_num_2 -> '>>' : '>>'.

% unary operators
_op_unary -> '!' : '!'.
_op_unary -> '-' : '-'.


%%%  ASSIGNMENT  %%%
_assignment -> _variable  '='  _expression
        : #rAssignment{
            var = '$1',   % _variable
            val = '$3'}.  % _expression


%%%  PARALLEL BLOCK  %%%
_parallel_block -> 'pardo'  '('  _par_arg  _opt_par_args  ')'  '{'  _body  '}'
        : ParArgs = ['$3' | '$4'],  % [par_arg | opt_par_args]
        #rParallelBlock{
            args = ParArgs,
            body = '$7'}.
_opt_par_args -> '$empty' : [].
_opt_par_args -> ','  _par_arg  _opt_par_args
        : ['$2' | '$3'].   % [par_arg | opt_par_args]


%%%  PARALLEL ARG  %%%
_par_arg -> _user_symbol  '='  _range
        : #rParallelArg{
            ident = '$1',
            range = '$3'}.


%%%  RANGE  %%%
_range -> _expression  '..'  _expression
        : #rRange{
            'begin' = '$1',
            'end' = '$3'}.


%%%  IF INSTRUCTION  %%%
_if_instr -> 'if'  '('  _expression  ')'  '{'  _body  '}' _opt_else
        : #rIfInstr{
            'cond' = '$3',
            then = '$6',
            else = '$8'}.
_opt_else -> '$empty'
        : #rBody{
            statements = []}.
_opt_else -> 'else'  '{'  _body  '}'
        : '$3'.


%%%  WHILE LOOP  %%%
_while_loop -> _opt_label  'while'  '('  _expression  ')'  '{'  _body  '}'
        : #rWhileLoop{
            label = '$1',
            'cond' = '$4',
            body = '$7'}.


%%%  FOR LOOP  %%%
_for_loop -> _opt_label  'for'  '('  _var_decl  ';'  _expression  ';'  _expression  ')'  '{'  _body  '}'
        : #rForLoop{
            label = '$1',
            varInit = '$4',
            'cond' = '$6',
            increment = '$8',
            body = '$11'}.

% label
_opt_label -> '$empty' : no_label.
_opt_label -> _user_symbol  ':'
        : '$1'.


%%%  LOOP CONTROL  %%%
_loop_control -> loop_ctrl  _opt_label
        : #rLoopControl{
            instr = element(3, '$1'),
            label = '$2'
        }.


%%%  RETURN INSTRUCTION  %%%
_return_instr -> return
        : #rReturnInstr{
            val = empty}.
_return_instr -> return  _expression
        : #rReturnInstr{
            val = '$2'}.


%%%  VAR _TYPE  %%%
_type -> simple_type
        : TypeName = element(3, '$1'),
        #rSimpleVarType{
            typeName = TypeName}.
_type -> _type  '['  ']'
        : #rArrayVarType{
            range = to_be_set_by_parser,
            baseType = '$1'}.
_array_type_range -> _range : '$1'.
_array_type_range -> _expression
        : #rRange{
            'begin' = make_int_const(0),
            'end' = #rBinaryExpr{
                op = '-',
                left = '$1',
                right = make_int_const(1)}}.
%TODO: być może kolejność kolejnych wymiarów tablicy powinna być odwrotna
%      (porównaj też z rArrayElement)


%%%  VAR DECL  %%%
_var_decl -> _type  _user_symbol  _many_var_decl_ranges  _opt_var_decl_value
        : Modifiers = [],
        HalfType = '$1',
        Ranges = '$3',
        Type = fill_type_with_ranges(HalfType, Ranges),
        make_rVarDecl(Modifiers, Type, '$2', '$4').
_var_decl -> _many_var_decl_modifiers  _type  _user_symbol  _many_var_decl_ranges  _opt_var_decl_value
        : format("full var_decl~n"),
        Modifiers = '$1',
        HalfType = '$2',
        Ranges = '$4',
        format("    half type: ~p~n    ranges: ~p~n", [HalfType, Ranges]),
        Type = fill_type_with_ranges(HalfType, Ranges),
        make_rVarDecl(Modifiers, Type, '$3', '$5').
_opt_var_decl_value -> '$empty' : empty.
_opt_var_decl_value -> '='  _expression : '$2'.
_many_var_decl_ranges -> '$empty' : [].
_many_var_decl_ranges -> '['  _array_type_range  ']'  _many_var_decl_ranges
        : ['$2' | '$4'].
_many_var_decl_modifiers -> var_modifier
        : Modifier = element(3, '$1'),
        [Modifier].
_many_var_decl_modifiers -> var_modifier  _many_var_decl_modifiers
        : Modifier = element(3,'$1'),
        format("found modifier: ~p~n", [Modifier]),
        [Modifier | '$2'].


%%%  VAR LOAD  %%%
_var_load -> 'load'  _user_symbol
        : #rVarLoad{
            ident = '$2'}.


%%%  VARIABLE  %%%
_variable -> _simple_variable : '$1'.
_variable -> _array_element   : '$1'.
_simple_variable -> _user_symbol
        : #rSimpleVariable{
            name = '$1'}.
_array_element -> _variable  '['  _expression  ']'
        : #rArrayElement{
            var = '$1',
            index = '$3'}.


%%%  CONST VALUE  %%%
_const_val -> positive_integer
        : PositiveValue = element(3, '$1'),
        make_int_const(PositiveValue).
_const_val -> '-'  positive_integer
        : PositiveValue = element(3, '$2'),
        make_int_const(-PositiveValue).
_const_val -> boolean
        : #rConstVal{
            type = ?BOOL,
            val = element(3, '$1')
        }.


%%%  FUN CALL  %%%
_fun_call -> _user_symbol  '('  _many_fun_call_args  ')'
        : #rFunctionCall{
            name = '$1',
            args = '$3'}.
_many_fun_call_args -> '$empty' : [].
_many_fun_call_args -> _fun_call_arg  _opt_fun_call_args
        : ['$1' | '$2'].
_opt_fun_call_args -> '$empty' : [].
_opt_fun_call_args -> ','  _fun_call_arg  _opt_fun_call_args
        : ['$2' | '$3'].
_fun_call_arg -> _expression
        : '$1'.


_user_symbol -> user_symbol
        : format("user symbol: ~p~n", [element(3,'$1')]),
        util:make_string(element(3,'$1')).




%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Erlang code.

-include("../../common/ast.hrl").

make_int_const(Val) when is_integer(Val) ->
    #rConstVal{
        type = ?INT,
        val = Val
    }.

fill_type_with_ranges(Type, _Ranges=[])
        when is_record(Type, rSimpleVarType) ->
    Type;
fill_type_with_ranges(Type, [Range | RangesTail])
        when is_record(Type, rArrayVarType),
        is_record(Range, rRange) ->
    Begin = Range#rRange.'begin',
    End   = Range#rRange.'end',
    BaseType = Type#rArrayVarType.baseType,
    Type#rArrayVarType{
        range = #rRange{'begin'=Begin, 'end'=End},
        baseType = fill_type_with_ranges(BaseType, RangesTail)
    };
fill_type_with_ranges(X, Y) ->
    throw({invalid_parameters, got, [X, Y]}).

make_rVarDecl(Modifiers, Type, VarName, Value) ->
    #rVarDecl{
        type = Type,
        ident = VarName,
        val = Value,
        isConst = lists:member(const, Modifiers),
        isInputVar = lists:member(input, Modifiers),
        isOutputVar = lists:member(output, Modifiers)
    }.

% enable/disable debug output
%%format(A, B) ->
%%    io:format(A, B).
%%format(A) ->
%%    io:format(A).
format(_A, _B) -> ok.
format(_A) -> ok.


