%%% @author Wade Mealing <wmealing@gmail.com>
%%% @copyright (C) 2026, Wade Mealing
%%% @doc
%%%
%%% @end
%%% Created : 25 Jan 2026 by Wade Mealing <wmealing@gmail.com>


-module(hit).


-export([fizzbuzz/4, distribute/0]).

distribute() ->
    Nodes = ['node1@localhost', 'node2@localhost', 'node3@localhost'],
    Total = 10,
    Count = length(Nodes),
    ChunkSize = Total div Count,
    Rem = Total rem Count,
    Tasks = [{lists:nth(I, Nodes), I,
              (I-1) * ChunkSize + min(I-1, Rem) + 1,
              I * ChunkSize + min(I, Rem)}
             || I <- lists:seq(1, Count)],

    Keys = [rpc:async_call(Node, hit, fizzbuzz, [self(), Idx, Start, End])
            || {Node, Idx, Start, End} <- Tasks],

    Results = [rpc:yield(Key) || Key <- Keys],

    Ordered = lists:keysort(2, Results),

    %% Simple nested comprehension: "For every result, and for every line in that result..."
    Combined = [{NodeName, Line} || {done, _, NodeName, Data} <- Ordered, Line <- Data],

    lists:foreach(fun({Node, Text}) ->
        io:format("Node: ~p | R: ~s~n", [Node, Text])
    end, Combined).


fizzbuzz(Parent, Index, Start, End) ->
    NumberList = lists:seq(Start, End),

    Solution = [solve(N) || N<- NumberList],
    Flattened = [lists:flatten(Sub) || Sub <- Solution],
    Parent ! {done, Index, node() , Flattened}.

solve(N) ->
    if N rem 15 == 0 ->
           io_lib:format("~p fizzbuzz", [N]);
       N rem 3 == 0 ->
           io_lib:format("~p fizz", [N]);
       N rem 5 == 0 ->
           io_lib:format("~p buzz", [N]);
       true ->
           io_lib:format("~p", [N])
    end.

