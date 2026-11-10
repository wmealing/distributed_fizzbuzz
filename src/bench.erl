%%% @author Wade Mealing <wmealing@gmail.com>
%%% @copyright (C) 2026, Wade Mealing
%%% @doc
%%% Times hit and fib, distributed across the cluster and on a single
%%% local process, so you can see what the network actually costs.
%%% Printing is not timed.
%%% @end
%%% Created : 10 Nov 2026 by Wade Mealing <wmealing@gmail.com>


-module(bench).


-export([run/0, run/2, run/3]).

-define(RUNS, 10).

run() ->
    run(hit, 1000),
    run(fib, 1000).

run(Module, Total) ->
    run(Module, Total, ?RUNS).

run(Module, Total, Runs) when (Module =:= hit orelse Module =:= fib),
                              is_integer(Total), Total > 0,
                              is_integer(Runs), Runs > 0 ->
    check(Module, Total),
    Distributed = time(fun() -> distributed(Module, Total) end, Runs),
    Local = time(fun() -> local(Module, Total) end, Runs),
    io:format("~p, N=~p, ~p runs (microseconds)~n", [Module, Total, Runs]),
    report("distributed", Distributed),
    report("local", Local),
    ok.


%% Fail loudly up front, rather than timing a run that lost a chunk.
check(fib, Total) ->
    case fib:collect(Total) of
        {_, []} -> ok;
        {_, Failed} -> erlang:error({nodes_failed, Failed})
    end;
check(hit, Total) ->
    Got = length(hit:collect(Total)),
    flush(),
    case Got of
        Total -> ok;
        _ -> erlang:error({missing_results, Total - Got})
    end.

distributed(fib, Total) -> fib:collect(Total);
distributed(hit, Total) -> hit:collect(Total), flush().

local(fib, Total) -> fib:sequence(1, 1, Total);
local(hit, Total) -> hit:fizzbuzz(self(), 1, 1, Total), flush().

%% hit:fizzbuzz/4 also sends its result to the caller. Drop those messages
%% so the mailbox doesn't grow and slow down later runs.
flush() ->
    receive {done, _, _, _} -> flush()
    after 0 -> ok
    end.

time(Fun, Runs) ->
    Fun(),
    lists:sort([element(1, timer:tc(Fun)) || _ <- lists:seq(1, Runs)]).

report(Label, Times) ->
    Runs = length(Times),
    Mean = lists:sum(Times) div Runs,
    io:format("  ~-12s min ~8w  median ~8w  mean ~8w  max ~8w~n",
              [Label, hd(Times), lists:nth((Runs + 1) div 2, Times),
               Mean, lists:last(Times)]).
