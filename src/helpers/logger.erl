%%%-------------------------------------------------------------------
%%% @author Gabriel Fortin
%%% @copyright 2015, Gabriel Fortin
%%% @doc
%%%
%%% @end
%%% Created : 25. Jul 2015 8:19 AM
%%%-------------------------------------------------------------------
-module(logger).
-author("Gabriel Fortin").

-behaviour(gen_server).



%% API
-export([
    start/0,
    start_link/0,
    log_enter/1, log_enter/2, log_enter/3,
    log_exit/1, log_exit/2, log_exit/3,
    log/2, log/3,
    set_filter_mode/1,
    get_filter_mode/0,
    filter_set/1]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-define(SERVER, ?MODULE).

-record(lstate, {
    % indentation level for output
    indent      = 0         :: integer(),
    % whether selected tags should be included in or excluded from output
    mode        = exclude   :: include | exclude,
    % tags that should be used for filtering
    tags        = []        :: [any()]
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
-spec start() -> {ok, Process | ignore | Error}
        when    Process     :: pid(),
                Error       :: {error, Reason :: term()}.
start() ->
    gen_server:start({local, ?SERVER}, ?MODULE, [], []).


%%--------------------------------------------------------------------
%% @doc
%% Starts the server and links it
%%
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, _Args=[], _Opts=[]).


%%--------------------------------------------------------------------
%% @doc
%% Logs a message and signals entering a function, block, ...
%%
%% This function will first print the log message (using the current
%% indentation level) and then increase the indentation level of logs.
%% Don't forget to call a corresponding {@link log_exit}.
%% @end
%%--------------------------------------------------------------------
-spec log_enter(_Tag) -> ok.
log_enter(Tag) ->
    log_enter("", Tag).
-spec log_enter(FormatText, _Tag) -> ok
        when    FormatText  :: string().
log_enter(FormatText, Tag) ->
    log_enter(FormatText, Tag, _NoArgs=[]).
-spec log_enter(FormatText, _Tag, Args) -> ok
        when    FormatText  :: string(),
                Args        :: list().
log_enter(FormatText, Tag, Args)
        when is_list(FormatText),
            is_list(Args) ->
    Res = gen_server:call(?SERVER, {log_and_indent, FormatText, [Tag | Args], +1, 'after'}),
    case Res of
        ok ->
            ok;
        {throw, T} ->
            throw(T);
        {error, E} ->
            error(E)
    end.


%%--------------------------------------------------------------------
%% @doc
%% Logs a message and signals exiting a function, block, ...
%%
%% This function will first decrease the indentation level of logs
%% and then print the log message (using the decreased indent).
%% It should be paired with a call to {@link log_enter}.
%% @end
%%--------------------------------------------------------------------
-spec log_exit(_Tag) -> ok.
log_exit(Tag) ->
    Res = gen_server:call(?SERVER, {log_and_indent, no_text, [Tag], -1, before}),
    case Res of
        ok ->
            ok;
        {throw, T} ->
            throw(T);
        {error, E} ->
            error(E)
    end.
-spec log_exit(FormatText, _Tag) -> ok
        when FormatText     :: string().
log_exit(FormatText, Tag) ->
    log_exit(FormatText, Tag, _NoArgs=[]).
-spec log_exit(FormatText, _Tag, Args) -> ok
        when    FormatText  :: string(),
                Args        :: list().
log_exit(FormatText, Tag, Args)
        when is_list(FormatText),
            is_list(Args) ->
    Res = gen_server:call(?SERVER, {log_and_indent, FormatText, [Tag | Args], -1, before}),
    case Res of
        ok ->
            ok;
        {throw, T} ->
            throw(T);
        {error, E} ->
            error(E)
    end.


%%--------------------------------------------------------------------
%% @doc
%% Logs a message.
%%
%% The current indentation level is used (and left unchaged).
%% @end
%%--------------------------------------------------------------------
-spec log(FormatText, _Tag) -> ok
        when    FormatText  :: string().
log(FormatText, Tag) ->
    log(FormatText, Tag, _NoArgs=[]).
-spec log(FormatText, _Tag, Args) -> ok
        when    FormatText  :: string(),
                Args        :: list().
log(FormatText, Tag, Args)
        when is_list(FormatText),
            is_list(Args) ->
    Res = gen_server:call(?SERVER, {log, FormatText, [Tag | Args]}),
    case Res of
        ok ->
            ok;
        {throw, T} ->
            throw(T);
        {error, E} ->
            error(E, [FormatText, Args])
    end.

%%--------------------------------------------------------------------
%% @doc
%% Sets the filtering mode.
%%
%% When set to 'include' only tags registered with {@link filter_set/1}
%% will be printed. When set to 'exclude' tags registered with
%% {@link fileter_set/1} will NOT be printed.
%% @end
%%--------------------------------------------------------------------
-spec set_filter_mode(Mode) -> ok
    when    Mode    :: include | exclude.
set_filter_mode(Mode)
        when Mode==include orelse Mode==exclude ->
    ok = gen_server:call(?SERVER, {filter_mode, Mode}).

%%--------------------------------------------------------------------
%% @doc
%% Gets the filtering mode.
%% @end
%%--------------------------------------------------------------------
-spec get_filter_mode() -> {ok, Mode}
    when    Mode    :: include | exclude.
get_filter_mode() ->
    {ok, _Mode} = gen_server:call(?SERVER, filter_mode).

%%--------------------------------------------------------------------
%% @doc
%% Sets the tags for output filtering.
%%
%% @end
%%--------------------------------------------------------------------
-spec filter_set(TagList) -> {ok, OldTagList}
        when    TagList     :: list(),
                OldTagList  :: list().
filter_set(TagList)
        when is_list(TagList) ->
    {ok, _OldTagsList} = gen_server:call(?SERVER, {filter_set, TagList}).


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
-spec init(Args :: term()) ->
    {ok, State :: #lstate{}} | {ok, State :: #lstate{}, timeout() | hibernate} |
    {stop, Reason :: term()} | ignore.
init([]) ->
    {ok, #lstate{}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #lstate{}) ->
    {reply, Reply :: term(), NewState :: #lstate{}} |
    {reply, Reply :: term(), NewState :: #lstate{}, timeout() | hibernate} |
    {noreply, NewState :: #lstate{}} |
    {noreply, NewState :: #lstate{}, timeout() | hibernate} |
    {stop, Reason :: term(), Reply :: term(), NewState :: #lstate{}} |
    {stop, Reason :: term(), NewState :: #lstate{}}).
handle_call({log_and_indent, Format, Args=[Tag | _], IndentSize, WhenIndent},
    _From, State) ->
    try
        case should_log(State, Tag) of
            no ->
                {reply, ok, State};
            yes ->
                NewIndent = State#lstate.indent + IndentSize,
                State_1 = State#lstate{indent = NewIndent},
                StateForPrint = case WhenIndent of
                                    before -> State_1;
                                    'after' -> State
                                end,
                print_log_text(Format, Args, StateForPrint),
                {reply, ok, State_1}
        end
    catch
        throw:T ->
            {reply, {throw, T}, State};
        error:E ->
            {reply, {error, E}, State}
    end;
handle_call({log, FormatText, Args=[Tag | _]}, _From, State) ->
    try
        case should_log(State, Tag) of
            no ->
                {reply, ok, State};
            yes ->
                print_log_text(FormatText, Args, State),
                {reply, ok, State}
        end
    catch
        throw:T ->
            {reply, {throw, T}, State};
        error:E ->
            {reply, {error, E}, State}
    end;
handle_call(filter_mode, _From, State) ->
    {reply, {ok, State#lstate.mode}, State};
handle_call({filter_mode, Mode}, _From, State) ->
    State_1 = State#lstate{mode = Mode},
    {reply, ok, State_1};
handle_call({filter_set, TagsList}, _From, State) ->
    OldTagsList = State#lstate.tags,
    State_1 = State#lstate{tags = TagsList},
    {reply, {ok, OldTagsList}, State_1};
handle_call(Request, _From, State) ->
    io:format("~p: handle call: unknown request: ~p~n", [?MODULE, Request]),
    {reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #lstate{}) ->
    {noreply, NewState :: #lstate{}} |
    {noreply, NewState :: #lstate{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #lstate{}}).
handle_cast(Request, State) ->
    io:format("~p: handle cast: unexpected; the request was: ~p~n", [?MODULE, Request]),
    {stop, not_supported, State}.

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
-spec(handle_info(Info :: timeout() | term(), State :: #lstate{}) ->
    {noreply, NewState :: #lstate{}} |
    {noreply, NewState :: #lstate{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #lstate{}}).
handle_info(Info, State) ->
    io:format("~p: handle info: unexpected; the info was: ~p~n", [?MODULE, Info]),
    {stop, not_supported, State}.

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
    State :: #lstate{}) -> term()).
terminate(Reason, _State) ->
    io:format("~p: terminate: reason: ~p~n", [?MODULE, Reason]),
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #lstate{},
    Extra :: term()) ->
    {ok, NewState :: #lstate{}} | {error, Reason :: term()}).
code_change(_OldVsn, _State, _Extra) ->
    {error, not_supported}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Verifies if the given module's logs should be printed or not.
%%
%% @end
%%--------------------------------------------------------------------
-spec should_log(State, _Tag) -> yes | no
        when    State   :: #lstate{}.
should_log(#lstate{mode = Mode, tags = TagsList}, Tag) ->
    IsMember = lists:member(Tag, TagsList),
    if
        Mode==include andalso IsMember ->
            yes;
        Mode==exclude andalso not IsMember ->
            yes;
        true ->
            no
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Prints the log text if there is any text to be printed.
%%
%% @end
%%--------------------------------------------------------------------
-spec print_log_text(Text, Args, State) -> ok
        when    Text    :: no_text | string(),
                Args    :: list(),
                State  :: #lstate{}.
print_log_text(no_text, _Args, State) ->
    Indentation = "~" ++ compute_indentation(State#lstate.indent, 0),
    io:format("~s<~n", [Indentation]),
    ok;
print_log_text(Text, Args, State)
        when is_list(Text),
            is_list(Args) ->
    Indentation = "~" ++ compute_indentation(State#lstate.indent, 0),
    io:format("~s[~p] " ++ Text ++ "~n", [Indentation | Args]).

compute_indentation(Size, _) when Size<0 ->
    throw({?MODULE, compute_indentation, indentation_size_is_negative});
compute_indentation(0, _) ->
    "";
compute_indentation(Size, Step)
        when    Step==5
    ->
    Res = compute_indentation(Size-1, 1),
    "'" ++ Res;
compute_indentation(Size, Step) ->
    Res = compute_indentation(Size-1, Step+1),
    " " ++ Res.
