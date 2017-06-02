%%%-------------------------------------------------------------------
%%% @author Gabriel Fortin
%%% @copyright (C) 2015, Gabriel Fortin
%%% @doc
%%%
%%% @end
%%% Created : 30. Aug 2015 11:34 AM
%%%-------------------------------------------------------------------
-module(io_server).
-author("Gabriel Fortin").

-behaviour(gen_server).


%% API
-export([
    read_from_file/1,   %% createes a new input server using a file name
    write_to_file/1,    %% creates a new output server using a file name
    read_int/1,         %% retrieves an integer from input
    write_int/2,        %% writes an integer to output
    close/1             %% closes the server
]).

%% gen_server callbacks
-export([
    init/1,         %% prepares the input (e.g. opens a file for reading)
    handle_call/3,  %% processes requests
    handle_cast/2,  %% required by the gen_server behaviour, unused
    handle_info/2,  %% required by the gen_server behaviour, unused
    terminate/2,    %% required by the gen_server behaviour, unused
    code_change/3   %% required by the gen_server behaviour, unused
]).


-record(iostate, {
    file        :: pid(), %%| fd()
    mode        :: read | write
}).


%%%===================================================================
%%% API
%%%===================================================================


%%--------------------------------------------------------------------
%% @doc
%% Creates a new input server. Data will be read from the file
%% whose name is the FileName argument.
%%
%% @end
%%--------------------------------------------------------------------
-spec read_from_file(FileName) -> {ok, IoServer} | {error, _Reason}
    when    FileName    :: string() | atom(),
            IoServer    :: pid().
read_from_file(FileName)
    when is_list(FileName) orelse is_atom(FileName)->
    ImplModule = ?MODULE,
    Args = {FileName, [read]},
    Options = [],
    gen_server:start_link(ImplModule, Args, Options).


%%--------------------------------------------------------------------
%% @doc
%% Creates a new output server. Data will be written to the file
%% whose name is the FileName argument.
%%
%% @end
%%--------------------------------------------------------------------
-spec write_to_file(FileName) -> {ok, IoServer} | {error, _Reason}
    when    FileName    :: string() | atom(),
            IoServer    :: pid().
write_to_file(FileName)
    when is_list(FileName) orelse is_atom(FileName)->
    ImplModule = ?MODULE,
    Args = {FileName, [write]},
    Options = [],
    gen_server:start_link(ImplModule, Args, Options).


%%--------------------------------------------------------------------
%% @doc
%% Tries to read the next data in the input as an integer value.
%%
%% @end
%%--------------------------------------------------------------------
-spec read_int(IoServer) -> {ok, Int} | {error, _Reason}
        when    IoServer    :: pid(),
                Int         :: integer().
read_int(IoServer)
        when is_pid(IoServer) ->
    case gen_server:call(IoServer, read_int) of
        {ok, Int} ->
            logger:log("read int => ~p", ?MODULE, [Int]),
            {ok, Int};
        {error, Reason} ->
            {error, Reason}
    end.


%%--------------------------------------------------------------------
%% @doc
%% Writes the given integer value to output.
%%
%% @end
%%--------------------------------------------------------------------
-spec write_int(IoServer, Value) -> ok | {error, _Reason}
        when    IoServer    :: pid(),
                Value       :: integer().
write_int(IoServer, Value)
        when is_pid(IoServer), is_integer(Value) ->
    case gen_server:call(IoServer, {write_int, Value}) of
        ok ->
            ok
    end.


%%--------------------------------------------------------------------
%% @doc
%% Closes the underlying file and terminates the server.
%%
%% @end
%%--------------------------------------------------------------------
-spec close(IoServer) -> ok | {error, _Reason}
        when    IoServer    :: pid().
close(IoServer) ->
    case gen_server:call(IoServer, close) of
        file_closed ->
            ok;
        {error, Reason} ->
            {error, Reason}
    end.




%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec init({FileName, Params}) -> {ok, State} | {stop, _Reason}
        when    FileName    :: string(),
                Params      :: [atom()],
                State       :: #iostate{}.
init({FileName, [read]}) ->
    case file:open(FileName, [read]) of
        {error, Reason} ->
            {stop, Reason};
        {ok, File} ->
            {ok, #iostate{
                file = File,
                mode = read
            }}
    end;
init({FileName, [write]}) ->
    case file:open(FileName, [write]) of
        {error, Reason} ->
            {stop, Reason};
        {ok, File} ->
            {ok, #iostate{
                file = File,
                mode = write
            }}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #iostate{}) ->
    {reply, Reply :: term(), NewState :: #iostate{}} |
    {reply, Reply :: term(), NewState :: #iostate{}, timeout() | hibernate} |
    {noreply, NewState :: #iostate{}} |
    {noreply, NewState :: #iostate{}, timeout() | hibernate} |
    {stop, Reason :: term(), Reply :: term(), NewState :: #iostate{}} |
    {stop, Reason :: term(), NewState :: #iostate{}}).
handle_call(read_int, _From, State) ->
    Response = case io:fread(State#iostate.file, "", "~d") of
        {ok, [Res]} ->
            {ok, Res};
        eof ->
            {error, eof};
        {error, Reason} ->
            {error, Reason}
    end,
    {reply, Response, State};
handle_call({write_int, Value}, _Fron, State) ->
    Response = case io:fwrite(State#iostate.file, "~w ", [Value]) of
        ok ->
            ok
    end,
    {reply, Response, State};
handle_call(close, _From, State) ->
    Response = case file:close(State#iostate.file) of
        ok ->
            ok;
        {error, Reason} ->
            {error, Reason}
    end,
    % TODO: finish this process gracefully (without an error report)
    {reply, file_closed, Response, State};
handle_call(AnythingElse, _From, State) ->
    io:format("ERROR: ~p: received an unrecognized gen_server callback~n"
            ++ "       request: ~p~n", [?MACHINE, AnythingElse]),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #iostate{}) ->
    {noreply, NewState :: #iostate{}} |
    {noreply, NewState :: #iostate{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #iostate{}}).
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
-spec(handle_info(Info :: timeout() | term(), State :: #iostate{}) ->
    {noreply, NewState :: #iostate{}} |
    {noreply, NewState :: #iostate{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #iostate{}}).
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
    State :: #iostate{}) -> term()).
terminate(_Reason, State) ->
    file:close(State#iostate.file),
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #iostate{},
    Extra :: term()) ->
    {ok, NewState :: #iostate{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
