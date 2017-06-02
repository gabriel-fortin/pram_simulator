%%%-------------------------------------------------------------------
%%% @author Gabriel Fortin
%%% @copyright (C) 2015, Gabriel Fortin
%%% @doc
%%%
%%% @end
%%% Created : 03. Jun 2015 7:34 PM
%%%-------------------------------------------------------------------
-author("Gabriel Fortin").

-export_type([
    tVarAddr/0,
    tMemModel/0,
    varProperty/0
]).


% generic timeout which is used, more or less, everywhere
-define(TIMEOUT, 7000).

-define(PROCESSOR_IMPL_MODULE, processor).
-define(MANAGER_IMPL_MODULE, manager).
-define(SCOPE_IMPL_MODULE, scope_impl).
-define(MEM_IMPL_MODULE, mem_impl).

-define(WORKER_RESTART_STRATEGY, transient).  % permanent, transient, or temporary
-define(WORKER_SHUTDOWN_TIMEOUT, 100).  % in milliseconds

-define(MANAGER_RESTART_STRATEGY, ?WORKER_RESTART_STRATEGY).
-define(MANAGER_SHUTDOWN_TIMEOUT, 1000).


-record(pram_args, {
    instance_name,
    program_file_name,
    input_file_name,
    output_file_name,
    memory_model,
    stats_command
}).


-type tMemModel()  :: 'EREW' | 'CREW' | 'CRCW common' | 'CRCW arbitrary' | 'CRCW priority'.


-record(var_addr, {
    addr            :: list(integer() | string() | bitstring())
}).
-type tVarAddr()    :: #var_addr{}.


% a variable held in memory or in scope
-record(variable, {
    name                    :: term(),
    type                    :: term(), % #rSimpleVarType{} | #rArrayVarType{}
    value                   :: any(),
    isGlobal        = false :: boolean(),
    isConst         = false :: boolean(),
    isInputVar      = false :: boolean(),
    isOutputVar     = false :: boolean()
}).
-type varProperty() :: const | global | input_var | output_var.
