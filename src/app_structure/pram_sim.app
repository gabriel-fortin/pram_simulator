%%%-------------------------------------------------------------------
%%% @author Gabriel Fortin
%%% @copyright (C) 2016, Gabriel Fortin
%%% @doc
%%%
%%% @end
%%% Created : 01. Mar 2016 8:41 PM
%%%-------------------------------------------------------------------
{application, pram_sim,
    [
        {description, "A simple interpreter for PRAM programs"},
        {vsn, "0.1.0"},
        %{modules, []},
        %{registered, []},
        {applications, [
            kernel,
            stdlib
        ]},
        {mod, { pram_sim, []}},
        {env, [
            {program_file, "manual_testing/program"},
            {input_file, "manual_testing/input"},
            {output_file, "manual_testing/output"},
            {stats_file, "manual_testing/stats"},
            {memory_model, 'CRCW common'}
        ]}
    ]}.

