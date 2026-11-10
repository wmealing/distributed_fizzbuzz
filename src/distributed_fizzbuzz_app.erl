%%%-------------------------------------------------------------------
%% @doc distributed_fizzbuzz public API
%% @end
%%%-------------------------------------------------------------------

-module(distributed_fizzbuzz_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    distributed_fizzbuzz_sup:start_link().

stop(_State) ->
    ok.

%% internal functions
