Introduction
------------

This project is an interpreter for a Parallel Random Access Machine (PRAM). Its aim is to execute
 code as is used in the theory of parallel computing but without the need to bother about hardware
 specific instructions. Also, the number of processors is not limited and can depend on input data.


HOW TO RUN THIS PROJECT
-----------------------

First, the scanner (tokenizer) and parser for the language need to be generated.
It is a one-time action.

    ./generate_scanner.sh
    ./generate_parser.sh

Next, the interpreter needs to be compiled.

    ./compile

Finally, the interpreter can be run against a program. There are some programs in the
 `manual_testing/` directory. For example, to run the _0060_basic_input_output_ program type

    ./silent_run.sh 0060

This will prepare _input_ and _expected_output_ files (in the _manual_testing/_ directory),
 run the program without printing logs, and compare the actual output against the expected one.

Many programs have multiple input/output file pairs prepared. By default, the first-found is
 chosen. In case you want a different one (say "02_14") type

    ./silent_run.sh 0060 02

To re-run the same setup type

    ./rerun.sh

This will run with the same program, input, and expected output files. It will also print
 a lot of logs to the standard output.


THE PARSER
----------

Running `./generate_parser.sh` will generate a parser file (an erlang source file) based on
 definitions located in the _src/parser_def.yrl_ file. The resulting _src/parser.erl_ file needs
 to be compiled with all other erlang source files.

To observe what is happening during parser generation and to see a more detailed summary
 after it finishes make sure that it has `{verbose, true}` among its options. For example,
  _generate_parser.sh_ could contain the following line:

    OPTIONS="[{parserfile, \"src/parser.erl\"}, {verbose, true}]"

Note: it is not erroneous that there are some shift/reduce conflicts in the parser - they are
 handled in a such way that the parser's output is correct. It is commonplace that grammars
 have ambiguities and in some cases it is better to leave those in the grammar, the alternative
 being an over-complicated grammar.


OVERALL SYSTEM DESIGN
---------------------

The working of the system from input files to output file consists of two parts:

  - program preparation - transformation of a program's text into an abstract syntax
     tree (AST), and
  - program execution - execution - transformation of input data into output data (based on program's
     AST) and oversight of this process (yielding an output of its own - that of the
     processing itself).

Transforming text to an AST representation of the program it represents consists of three
 parts where the last one is optional:
 
  - scanning - text is divided into tokens - atomic parts of the program's text,
  - parsing - an abstract syntax tree (AST) of the program is built from tokens,
  - validation - AST is checked for nodes' type correctness; (more static analysis could
     be implemented as a part of this stage).

Program execution is composed of two phases:

  - pre-execution - when input is read; memory and scope are prepared and filled with
     initial and input data; global variables are declared and (optionally) initialised,
  - proper-execution - when the main function of a program is executed; synchronisation, memory
     model oversight, and work measurement are being switched on.

Program execution is possible as the result of the cooperation of several components
 (each implemented as a separate module):

  - memory - global, shared memory; the only place where arrays can be stored; access to
     it is supervised with respect to the current memory model,
  - scope - where a processor looks up when accessing a variable; stores variables local
     for its client (a processor) and knows whether a global variable exists; stores definitions
     of functions; exposes the possibility to nest contexts to allow dealing with nested
     blocks of code (shadowing variables and "forgetting" them),
  - processor - performs execution of code by visiting AST nodes of the program; makes use
     of a scope, memory, and a manager; it is meant for the proper-execution phase and is the
     core element of it but it is also used during pre-execution as a computation helper,
  - manager - performs most of the pre-execution phase tasks only relaying computation of
     expressions to a processor; is responsible for synchronisation during the proper-execution
     phase


BARRIERS
--------

Barriers' purpose is to imitate a PRAM's property which can be phrased as "synchronous parallel
 execution" - at a given moment in time all processors are "at" the same instruction.
 **((citation/reference needed))**

Barriers are for mimicking processors' idling. There is a single, common
 instruction pointer (IP) in a PRAM used by _all_ processors. Therefore, if the execution
 on two processors diverges (let's say because of an "if-else" branching) then both of them
 would "follow" both branches. The difference is that one processor would actually
 execute instructions while the other would idle - waiting for its turn (for the other branch to
 be executed) or until both processors' execution converges.
 **((citation for NOP - what it is etc.))**

A manager's clients syncing on a barrier are not taken into account when an "on-clock"
 **((TODO: define somewhere what an "on-clock" event is))**
 synchronisation is happening. After requesting to be synchronised on a barrier, a client
 (usually, a processor) is no longer seen as "running" and will not be waited upon during
 "on-clock" synchronisation.

A barrier sync event can happen only if all of the following conditions occur together:

  - there are no "running" processors,
  - there are no processors waiting for an "on-clock" event,
  - there are not processors waiting to obtain a barrier.

For an if-else statement the use of barriers implies that the second branch cannot be executed
 until the execution of the first branch has finished. Similarly, the code after the if-else
 statement cannot be executed until the execution of the second branch has finished.

To enforce that in the implementation, at the beginning of an if-else statement all "running"
 processors request two barriers from the manager. In the first stage processors that chose
 to execute the "false" branch will sync on the first barrier immediately. Processors that
 chose to execute the "true" branch will execute it and then sync on the
 first barrier. When that happens, all processors (involved in this barrier) resume execution.

The second stage is analogous. This time processors that chose to execute the "true" branch sync
 on the second barrier immediately. Processors that chose to execute the "false" branch will
 execute that branch and then sync on the second barrier. When that happens, all processors
 (involved in this barrier) resume execution - they are to execute the same code back again.
 **((TODO: find better names for "false"/"true" branches))**
 **((TODO: maybe define somewhere what a "running" processor is))**


The situation gets a little more complicated in the case of loops but follows the same principles.
 

Synchronisation on barriers works correctly also when branching statements are nested.
 When a barrier is requested, the number of requesting processors is stored in the
 barrier record. The same number of processors must request a barrier sync before
 an event is sent to processors waiting for this barrier. As a processor is able to
 sync only on a barrier which it requested earlier we can be sure that the set of processors
 that sync on a barrier is the exact same set of processors that requested it.


PRE-EXECUTION PHASE
-------------------

Near the beginning we create a _Memory_ process and a _Scope_ process. Before the
 proper-execution phase begins they will be prepared - populated with variables' "cells"
 **((TODO: find a better word than "cells"))**
 and data from input will be read into those marked as "input" variables. Also, functions'
 declarations will be added to _Scope_.

Functions must be extracted from the program's AST. That is easy - iterating over top-level
 statements of the program and selecting those representing a function declaration is enough.
 Extracted functions are put into the _Scope_.

The matter is more complicated for the initialisation of variables (preparing "cells" in
 _Scope_ and _Memory_) and the loading of variables (filling those "cells" with input data).
First, variable declaration statements and variable load statements are extracted from the
 program's AST (analogously to functions' declarations). Then, they are iterated over in the
 order of appearance in the program. It implies that the order of load statements defines the
 meaning of input data.
 
The processing of a variable declaration may require other variables to be initialised.
 <br/>For example:
 
    input int[] t[x..y];
    
This statement is a declaration of an array whose indices range from "x" to "y". It needs
 variables "x" and "y" to be initialised in advance. Not initialising a variable before
 referencing it (in another variable's declaration) is an error. The term "initialising
 a variable" means either providing an expression in the variable's declaration (which
 is not possible for arrays) or providing a load statement for that variable.

... **((TODO: reading/writing multidimensional arrays - indices' use order))**



STATS
-----
The system provides data on some aspects of the proper execution phase. Those are:
  - cycles - the number of time units needed for the proper-execution phase (emitting
      a synchronisation event is the de facto time unit),
  - work - the number of operations needed in the proper-execution phase; in
      a single-processor setup it is equivalent to the execution time (number of cycles),
  - cost - the product of the number of processors "allocated for work" (registered in manager)
      and the time during which they are needed (measured in time units); similar to work but
      idling processors are also taken into account,
  - max_processors - the maximum number of processors "allocated" at any given time of the
      proper-execution phase.



LANGUAGE RULES
--------------

Here are listed non-obvious rules/features/aspects of the language:

  -  the order of load statements matters,
  -  a variable cannot be loaded more that once,
  -  a variable must be initialised before it's referenced in another variable's declaration
  -  arrays can be only global,
  - ! "if-then", "if-then-else", "while", "for" statements require blocks
  -  variables in 'forprocessor' statements are (implicitly) of integer type
  - ?(need to verify) there is not function overloading
  - ! currently, only integer variables are allowed for input/output
  - ! the order of reading and writing of elements of a multidimensional array may be surprising
      (but will reworked in the future)
  - in case of multiple "output" variables they will be written out in arbitrary order
  - 



WHAT COULD BE ADDED
-------------------

Here goes an (obviously incomplete) list of features that could be added or improved:

  - static code analysis - many errors could be revealed during the validation process
     instead of during execution,
  - communicating errors to the user - this is a very general point; reported errors could be
     more informative in both meaning and localisation of the problem,
  - IDs for every node of the AST - can be used to report where in the program an error
     happened; can be used to trace back the erroneous line of code if instead of a simple ID
     we store a record containing the source file line number and other data,
  - per instance logging to dedicated log files - currently all logs from all pram instances
     are printed to stdout
  - more syntactic features (increment instruction, for example)
  -
