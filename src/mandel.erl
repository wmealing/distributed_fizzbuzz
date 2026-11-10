%%% @author Wade Mealing <wmealing@gmail.com>
%%% @copyright (C) 2026, Wade Mealing
%%% @doc
%%% Distributed Mandelbrot. Rows are dealt out round-robin, so every node
%%% gets a fair share of the expensive rows through the middle of the set.
%%% Each node sends back one binary of grey pixels per row, and the caller
%%% stitches them into a PGM image.
%%% @end
%%% Created : 10 Nov 2026 by Wade Mealing <wmealing@gmail.com>

-module(mandel).

-export([
    render/3,
    distribute/0, distribute/1, distribute/2,
    collect/1, collect/2,
    width/1,
    workers/1
]).

-define(MAX_ITER, 1000).
-define(OUTPUT, "mandelbrot.pgm").

distribute() ->
    distribute(800).

distribute(Height) ->
    distribute(Height, workers([node() | nodes()])).

distribute(Height, Nodes) ->
    {Time, {Rows, Failed}} = timer:tc(fun() -> collect(Height, Nodes) end),
    lists:foreach(
        fun({Node, Reason}) ->
            io:format("Node: ~p | FAILED: ~p~n", [Node, Reason])
        end,
        Failed
    ),
    lists:foreach(
        fun(Node) ->
            io:format(
                "Node: ~p | rows: ~p~n",
                [Node, length([Y || {Y, N, _} <- Rows, N =:= Node])]
            )
        end,
        lists:usort(Nodes)
    ),
    io:format("Rendered ~px~p in ~p ms~n", [width(Height), Height, Time div 1000]),
    case Failed of
        [] -> write_pgm(?OUTPUT, width(Height), Height, Rows);
        _ -> {error, Failed}
    end.

collect(Height) ->
    collect(Height, workers([node() | nodes()])).

collect(Height, Nodes) when is_integer(Height), Height > 0, Nodes =/= [] ->
    Width = width(Height),
    Count = length(Nodes),
    Tasks = [
        {Node, lists:seq(I - 1, Height - 1, Count)}
     || {I, Node} <- lists:zip(lists:seq(1, Count), Nodes)
    ],

    Keys = [
        {Node, rpc:async_call(Node, mandel, render, [Width, Height, Ys])}
     || {Node, Ys} <- Tasks
    ],

    Results = [{Node, rpc:yield(Key)} || {Node, Key} <- Keys],

    Failed = [{Node, Reason} || {Node, {badrpc, Reason}} <- Results],

    Rows = lists:keysort(1, [
        {Y, Node, Bin}
     || {Node, Lines} <- Results,
        is_list(Lines),
        {Y, Bin} <- Lines
    ]),
    {Rows, Failed}.

%% One entry per scheduler on each node, so every core gets rows.
%% An unreachable node still gets one entry, so collect/2 reports it.
workers(Nodes) ->
    lists:append([lists:duplicate(cores(Node), Node) || Node <- Nodes]).

cores(Node) ->
    case rpc:call(Node, erlang, system_info, [schedulers_online]) of
        N when is_integer(N) -> N;
        _ -> 1
    end.

%% The view is 3 units wide and 2 tall, so keep the pixels square.
width(Height) ->
    Height * 3 div 2.

render(Width, Height, Ys) ->
    [{Y, row(Y, Width, Height)} || Y <- Ys].

row(Y, Width, Height) ->
    Ci = 1.0 - 2.0 * (Y + 0.5) / Height,
    <<
        <<(shade(escape(-2.0 + 3.0 * (X + 0.5) / Width, Ci))):8>>
     || X <- lists:seq(0, Width - 1)
    >>.

escape(Cr, Ci) ->
    escape(0.0, 0.0, Cr, Ci, 0).

escape(_, _, _, _, ?MAX_ITER) ->
    ?MAX_ITER;
escape(Zr, Zi, Cr, Ci, N) ->
    step(Zr * Zr, Zi * Zi, Zr, Zi, Cr, Ci, N).

step(Zr2, Zi2, _, _, _, _, N) when Zr2 + Zi2 > 4.0 ->
    N;
step(Zr2, Zi2, Zr, Zi, Cr, Ci, N) ->
    escape(Zr2 - Zi2 + Cr, 2.0 * Zr * Zi + Ci, Cr, Ci, N + 1).

%% Inside the set is black. Outside, brighter means it took longer to escape.
shade(?MAX_ITER) -> 0;
shade(N) -> round(255 * math:log(N + 1) / math:log(?MAX_ITER)).

write_pgm(File, Width, Height, Rows) ->
    Header = io_lib:format("P5~n~p ~p~n255~n", [Width, Height]),
    ok = file:write_file(File, [Header | [Bin || {_, _, Bin} <- Rows]]),
    {ok, File}.
