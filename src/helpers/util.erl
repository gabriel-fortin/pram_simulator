%%%-------------------------------------------------------------------
%%% @author Gabriel Fortin
%%% @copyright (C) 2015, Gabriel Fortin
%%% @doc
%%%
%%% @end
%%% Created : 30. May 2015 9:52 PM
%%%-------------------------------------------------------------------
-module(util).
-author("Gabriel Fortin").

-include("../common/ast.hrl").
-include("../common/defs.hrl").


%% API
-export([
    send_async/2, send_sync/2, send_sync/3, reply/2,
    dereference/1, dereference_decl/1,
    make_string/1, ensure_string_type/1,
    extract_var_properties/1, ensure_properties_are_valid/1,
    ensure_type_is_canonical/1,
    get_base_type/1,
    make_variable/3
]).

-define(VALID_VAR_PROPERTIES, [const, global, input_var, output_var]).


%%--------------------------------------------------------------------
%% @doc
%% Sends an asynchronous message.
%%
%% A call to this function sends the given message to the given
%% recipient and returns immediately.
%% @end
%%--------------------------------------------------------------------
-spec send_async(Recipient, Message) -> ok
        when    Recipient   :: pid(),
                Message     :: any().
send_async(Recipient, Msg)
        when is_pid(Recipient) ->
    Recipient ! {async, Msg},
    ok.


%%--------------------------------------------------------------------
%% @doc
%% Sends a synchronous message.
%%
%% A call to this function sends the given message to the given
%% recipient and waits until a response is received.
%% @end
%%--------------------------------------------------------------------
-spec send_sync(Recipient, Message) -> Response
        when    Recipient   :: pid(),
                Message     :: any(),
                Response    :: any().
send_sync(Recipient, Msg)
        when is_pid(Recipient) ->
    Ref = make_ref(),
    Recipient ! {{self(), Ref}, Msg},
    receive
        {Ref, Response} ->
            Response
    end.


%%--------------------------------------------------------------------
%% @doc
%% Sends a synchronous message with timeout.
%%
%% A call to this function sends the given message to the given
%% recipient and waits until either: <br />
%%   - a response is received, or <br />
%%   - the time given as <code>Timeout</code> elapses.
%% @end
%%--------------------------------------------------------------------
-spec send_sync(Recipient, Message, Timeout) -> Response
        when    Recipient   :: pid(),
                Message     :: any(),
                Response    :: any(),
                Timeout     :: non_neg_integer().
send_sync(Recipient, Msg, Timeout)
        when is_pid(Recipient),
            is_integer(Timeout),
            Timeout >= 0 ->
    Ref = make_ref(),
    Recipient ! {{self(), Ref}, Msg},
    receive
        {Ref, Response} ->
            Response
    after Timeout ->
        throw({timeout, {recipient, Recipient}, {msg, Msg}})
    end.


%%--------------------------------------------------------------------
%% @doc
%% Answers a <code>send_sync</code>'s message.
%%
%% Answers a message sent previously with {@link send_sync/2} or
%% {@link send_sync/3}. <br />
%% The first element of a received message's tuple is a token. This
%% token must be used in the response in order to answer in the same
%% "communication channel".
%% @end
%%--------------------------------------------------------------------
-spec reply(Token, Response) -> ok
        when    Token       :: {pid(), reference()},
                Response    :: any().
reply({Sender, Ref}, Msg)
        when is_pid(Sender),
            is_reference(Ref) ->
    Sender ! {Ref, Msg},
    ok.


%%--------------------------------------------------------------------
%% @doc
%% Translates a variable's usage node into an address.
%%
%% Memory cells (either global or local) should be <i>accessed</i>
%% only with addresses generated by this function. <br />
%% Internally, the address format consist of the variable's name and
%% eventual indices (if the variable is an array).
%% @end
%%--------------------------------------------------------------------
-spec dereference(Variable) -> VarAddr
        when    Variable    :: tVarType(),
                VarAddr     :: tVarAddr().
dereference(Variable)
        when is_record(Variable, rSimpleVariable) orelse is_record(Variable, rArrayElement) ->
    Result = internal_dereference(Variable),
    logger:log("dereference => ~150p", ?MODULE, [Result]),
    Result.

%% @private
internal_dereference(#rSimpleVariable{name = Name}) ->
    #var_addr{addr = [Name]};
internal_dereference(#rArrayElement{var = Var,
        index = #rConstVal{type = #rSimpleVarType{typeName = int}, val = Index}}) ->
    #var_addr{addr = Addr} = internal_dereference(Var),
    #var_addr{addr = [Index | Addr]}.


%%--------------------------------------------------------------------
%% @doc
%% Translates a variable's declaration into all of its possible
%% addresses.
%%
%% Memory cells (either global or local) should be <i>created</i>
%% only with addresses generated by this function. <br />
%% Example: the following variable declaration:
%% <code>int[] foo[1..3];</code> <br />
%% will yield the following list of addresses:
%% <code>[ [1,"foo"], [2,"foo"], [3,"foo"] ]</code>.
%% @end
%%--------------------------------------------------------------------
-spec dereference_decl(VarDeclaration) -> VarAddress
        when    VarDeclaration  :: tVarDecl(),
                VarAddress      :: tVarAddr().
dereference_decl(#rVarDecl{type = Type, ident = Name}) ->
    BaseResult = [#var_addr{addr = [Name]}],
    FullResult = internal_dereference_decl(BaseResult, Type),
    logger:log("dereference decl: result: ~p", ?MODULE, [FullResult]),
    FullResult.

%% @private
internal_dereference_decl(PartialResult, #rSimpleVarType{}) ->
    PartialResult;
internal_dereference_decl(PartialResult, #rArrayVarType{baseType = BaseType, range = Range}) ->
    Begin = Range#rRange.'begin'#rConstVal.val,
    End = Range#rRange.'end'#rConstVal.val,
    ArrayCells = [ #var_addr{addr = [Index | Addr#var_addr.addr]} ||
            Addr <- PartialResult,
            Index <- lists:seq(Begin, End) ],
    internal_dereference_decl(ArrayCells, BaseType).


%%--------------------------------------------------------------------
%% @doc
%% Transforms a string to a representation proper for the current setup.
%%
%% Creates a string depending on wheter regular or binary representation
%% is used. The argument is a regular string (a list of chars).
%% @end
%%--------------------------------------------------------------------
-spec make_string(ArgString) -> ProperRepresentation
        when    ArgString               :: string(),
                ProperRepresentation    :: string() | bitstring().
%% % binary representation (better performance)
%% make_string(Arg)
%%         when is_list(Arg) ->
%%     list_to_binary(Arg);

% canonical representation (better readability)
make_string(Arg)
        when is_list(Arg) ->
    Arg;  % return the argument unchanged

make_string(InvalidArg) ->
    logger:log("invalid argument to 'make_string()'; expected a string, got ~p",
        [InvalidArg]),
    invalid_argument.


%%--------------------------------------------------------------------
%% @doc
%% Makes sure that the given string has the proper representation
%% (usefullness of this is doubtful).
%%
%% @end
%%--------------------------------------------------------------------
ensure_string_type(Arg) when is_list(Arg) ->  % if regular strings
    ok;
%% ensure_string_type(Arg) when is_bitstring(Arg) ->  % if binary strings
%%     ok;
ensure_string_type(_) ->
    throw(incorrect_string_type).


%%--------------------------------------------------------------------
%% @doc
%% Extracts properties of a var declaration and returns them as a list.
%%
%% @end
%%--------------------------------------------------------------------
-spec extract_var_properties(Var) -> Properties
        when    Var         :: tVarDecl() | #variable{},
                Properties  :: [varProperty()].
extract_var_properties(VarDecl) when is_record(VarDecl, rVarDecl) ->
    Properties = [
        {const,      VarDecl#rVarDecl.isConst},
        {global,     VarDecl#rVarDecl.isGlobal},
        {input_var,  VarDecl#rVarDecl.isInputVar},
        {output_var, VarDecl#rVarDecl.isOutputVar}],
    [ Prop || {Prop, IsSet} <- Properties, IsSet];
extract_var_properties(Variable) when is_record(Variable, variable) ->
    Properties = [
        {const,      Variable#variable.isConst},
        {global,     Variable#variable.isGlobal},
        {input_var,  Variable#variable.isInputVar},
        {output_var, Variable#variable.isOutputVar}],
    [ Prop || {Prop, IsSet} <- Properties, IsSet].


%%--------------------------------------------------------------------
%% @doc
%% Ensures that the given atoms are valid var properties.
%%
%% Valid var properties are: <code>global</code>,
%% <code>const</code>, <code>input_var</code>,
%% <code>output_var</code>.
%% @end
%%--------------------------------------------------------------------
-spec ensure_properties_are_valid(VarProperties) -> boolean()
        when    VarProperties :: [varProperty()].
ensure_properties_are_valid(VarProperties) ->
    lists:all(
        fun(Elem) ->
            lists:member(Elem, ?VALID_VAR_PROPERTIES)
        end,
        VarProperties).


%%--------------------------------------------------------------------
%% @doc
%% Ensures that the given type is in the simplest possible form. In
%% other words, it cannot be simplified by substituting a var occurrence
%% by its value, for example.
%%
%% @throws {type_is_not_canonical, VarType}
%% @end
%%--------------------------------------------------------------------
-spec ensure_type_is_canonical(VarType) -> ok | no_return()
        when    VarType     :: tVarType().
ensure_type_is_canonical(#rSimpleVarType{}) ->
    ok;
ensure_type_is_canonical(#rArrayVarType{
            baseType = BaseType,
            range = #rRange{'begin' = Begin, 'end' = End}})
        when is_record(Begin, rConstVal), is_record(End, rConstVal) ->
    ensure_type_is_canonical(BaseType);
ensure_type_is_canonical(ANonCanonicalType) ->
    throw({type_is_not_canonical, ANonCanonicalType}).


%%--------------------------------------------------------------------
%% @doc
%% Returns the same type for a simple type and the base type for an array.
%%
%% Given a type that is possibly an array returns the type that a memory
%% cell for it will have.
%%
%% @end
%%--------------------------------------------------------------------
-spec get_base_type(Type) -> #rSimpleVarType{}
    when    Type        :: #rSimpleVarType{} | #rSimpleVarType{}.
get_base_type(SimpleType) when is_record(SimpleType, rSimpleVarType) ->
    SimpleType;
get_base_type(#rArrayVarType{baseType = BaseType}) ->
    get_base_type(BaseType).


%%--------------------------------------------------------------------
%% @doc
%% A shorthand for creating a <code>#variable{}</code> record.
%% <code>VarProperties</code> and <code>VarType</code> are validated.
%%
%% @end
%%--------------------------------------------------------------------
-spec make_variable(VarAddr, VarType, VarProperties) -> #variable{}
        when    VarAddr         :: tVarAddr(),
                VarType         :: tVarType(),
                VarProperties   :: [varProperty()].
make_variable(VarAddr, VarType, VarProperties) ->
    ensure_properties_are_valid(VarProperties),
    ensure_type_is_canonical(VarType),
    #variable{
        name = VarAddr,
        type = VarType,
        isConst = lists:member(const, VarProperties),
        isGlobal = lists:member(global, VarProperties),
        isInputVar = lists:member(input_var, VarProperties),
        isOutputVar = lists:member(output_var, VarProperties)
    }.
