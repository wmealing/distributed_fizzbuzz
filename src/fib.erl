%%% @author Wade Mealing <wmealing@gmail.com>
%%% @copyright (C) 2026, Wade Mealing
%%% @doc
%%% Distributed Fibonacci. Each node uses fast doubling to jump straight
%%% to the start of its chunk, then counts forward with plain addition.
%%% @end
%%% Created : 10 Nov 2026 by Wade Mealing <wmealing@gmail.com>

-module(fib).

-export([sequence/3, distribute/0, distribute/1, collect/1]).

distribute() ->
    distribute(100).

distribute(Total) ->
    {Combined, Failed} = collect(Total),
    lists:foreach(
        fun({Node, Reason}) ->
            io:format("Node: ~p | FAILED: ~p~n", [Node, Reason])
        end,
        Failed
    ),
    lists:foreach(
        fun({Node, N, F}) ->
            io:format("Node: ~p | F(~p) = ~p~n", [Node, N, F])
        end,
        Combined
    ).

collect(Total) when is_integer(Total), Total > 0 ->
    Nodes = ['node1@localhost', 'node2@localhost', 'node3@localhost'],
    Count = length(Nodes),
    ChunkSize = Total div Count,
    Rem = Total rem Count,
    Tasks = [
        {
            lists:nth(I, Nodes),
            I,
            (I - 1) * ChunkSize + min(I - 1, Rem) + 1,
            I * ChunkSize + min(I, Rem)
        }
     || I <- lists:seq(1, Count)
    ],

    Keys = [
        {Node, rpc:async_call(Node, fib, sequence, [Idx, Start, End])}
     || {Node, Idx, Start, End} <- Tasks
    ],

    Results = [{Node, rpc:yield(Key)} || {Node, Key} <- Keys],

    Failed = [{Node, Reason} || {Node, {badrpc, Reason}} <- Results],

    Ordered = lists:keysort(2, [R || {_, {done, _, _, _} = R} <- Results]),

    Combined = [{NodeName, N, F} || {done, _, NodeName, Data} <- Ordered, {N, F} <- Data],
    {Combined, Failed}.

sequence(Index, Start, End) when Start > End ->
    {done, Index, node(), []};
sequence(Index, Start, End) ->
    {A, B} = pair(Start),
    {done, Index, node(), count(Start, End, A, B)}.

%% A = F(N), B = F(N+1)
count(N, End, _, _) when N > End -> [];
count(N, End, A, B) -> [{N, A} | count(N + 1, End, B, A + B)].

%% Fast doubling: returns {F(N), F(N+1)}.
pair(0) ->
    {0, 1};
pair(N) ->
    {A, B} = pair(N div 2),
    C = A * (2 * B - A),
    D = A * A + B * B,
    case N rem 2 of
        0 -> {C, D};
        1 -> {D, C + D}
    end.
