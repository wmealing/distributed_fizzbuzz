distributed_fizzbuzz
=====

FizzBuzz, but spread across a cluster of Erlang nodes. Because some problems
are too important to trust to a single machine.

`hit:distribute/0` splits the range 1..1000 into contiguous chunks, sends one
chunk to each of three nodes with `rpc:async_call/4`, waits for every node to
answer, puts the results back in order and prints each line along with the
node that computed it.

Build
-----

    $ rebar3 compile

Running across three nodes
--------------------------

The node names are hardcoded in `src/hit.erl` as `node1@localhost`,
`node2@localhost` and `node3@localhost`. All three nodes need the same cookie
and the compiled `hit` module on their code path.

Open three terminals in the project directory and start one node in each:

    $ rebar3 shell --sname node1@localhost --setcookie fizz
    $ rebar3 shell --sname node2@localhost --setcookie fizz
    $ rebar3 shell --sname node3@localhost --setcookie fizz

If you'd rather not use rebar3 shell, plain `erl` works too:

    $ erl -sname node1@localhost -setcookie fizz -pa _build/default/lib/distributed_fizzbuzz/ebin

You don't have to connect the nodes by hand. Distributed Erlang connects them
the first time one node makes an RPC call to another. From any of the three
shells:

    1> hit:distribute().
    Node: node1@localhost | R: 1
    Node: node1@localhost | R: 2
    Node: node1@localhost | R: 3 fizz
    ...
    Node: node1@localhost | R: 334
    Node: node2@localhost | R: 335 buzz
    ...
    Node: node2@localhost | R: 667
    Node: node3@localhost | R: 668
    ...
    Node: node3@localhost | R: 999 fizz
    Node: node3@localhost | R: 1000 buzz
    ok

The range is split as evenly as it can be. When it doesn't divide evenly, the
first nodes each get one extra number, so 1000 numbers on 3 nodes become
334, 333 and 333.

### Running on separate machines

1. Change the node list in `hit:distribute/1` to real hostnames, such as
   `'node1@host-a'`.
2. Start each node with `-sname` if the hosts resolve each other by short
   name, or with `-name node1@host-a.example.com` for fully qualified names.
   A cluster can't mix the two.
3. Use the same cookie everywhere, either with `-setcookie` or with an
   identical `~/.erlang.cookie` on each host.
4. Allow traffic to EPMD (port 4369) and to the distribution ports between
   the hosts.
5. Copy the compiled `.beam` files to each host, or load the module from one
   node with `nl(hit).` once the nodes are connected.

### Changing the workload

`hit:distribute/0` runs 1..1000. To pick your own range, pass the upper bound
to `hit:distribute/1`:

    1> hit:distribute(20).
    Node: node1@localhost | R: 1
    ...
    Node: node3@localhost | R: 20 buzz
    ok

The node list is still hardcoded at the top of `hit:distribute/1`. Edit it and
recompile (or run `r3:compile().` inside `rebar3 shell`) to try other cluster
shapes.

Benefits of distributed FizzBuzz
--------------------------------

To be clear, nobody needs distributed FizzBuzz. It is a small, familiar
problem you can use to explore Erlang distribution without the domain logic
getting in the way. As a learning exercise it has real benefits:

- **Shows the scatter/gather pattern clearly.** You split the work, fan it
  out with `rpc:async_call`, collect it with `rpc:yield` and reassemble it.
  The same pattern drives real map-reduce jobs.
- **Proves location transparency.** The code that runs on a remote node is
  the same as the code that runs locally. Only the node name changes.
- **Makes ordering visible.** The nodes may finish in any order, and
  `lists:keysort/2` on the chunk index restores the sequence. Tagging every
  line with its node shows who computed what.
- **Scales horizontally, in theory.** Add a node to the list and every node
  gets a smaller chunk. With a big enough range and expensive enough work per
  number, the extra nodes do cut wall-clock time.
- **No dependencies.** It uses only `kernel` and `stdlib`, so the whole thing
  fits in your head.

Drawbacks of distributed FizzBuzz
---------------------------------

- **It's much slower than plain FizzBuzz.** Each number costs a few
  nanoseconds to compute, while each RPC round-trip costs tens of
  microseconds on localhost and milliseconds over a real network. The network
  costs far more than the work it carries.
- **Results come back as strings.** Every line is formatted on the worker and
  copied back to the caller, so the data you move grows with the range. A
  single node could generate it with no copying at all.
- **One failure loses the whole run.** If any node is down or unreachable,
  `rpc:yield/1` returns `{badrpc, nodedown}` for that chunk. The comprehension
  in `distribute/1` then skips that chunk without a word, and you get
  FizzBuzz with a gap in it. There are no retries and no reassignment to a
  healthy node.
- **The cluster is static.** The node list is hardcoded, so you can't add or
  remove nodes at runtime. Real systems discover nodes, with `nodes()`, `pg`
  or a library like libcluster, instead of listing them.
- **Every node needs the code.** You have to deploy `hit.beam` to each node
  and keep the copies in sync. A version mismatch gives `undef` errors or,
  worse, subtly different output.
- **Erlang distribution is not secure by default.** The cookie is a shared
  secret, not real authentication, and traffic is unencrypted unless you set
  up TLS distribution. Any node that has the cookie gets full remote code
  execution on every node in the cluster.
- **It leaves messages behind.** `fizzbuzz/4` sends its result to `Parent`
  and also returns it as the RPC result. The caller uses the return value and
  never receives the message, so each call to `distribute` leaves one
  `{done, ...}` message per node in the calling process's mailbox. In a
  long-lived shell these pile up. Run `flush().` to see them.
- **The output is gathered before it is printed.** Nothing is printed until
  the slowest node answers, so one slow node holds up the whole result.

Quick local smoke test
----------------------

To run all three nodes from one terminal without interactive shells:

    $ EBIN=_build/default/lib/distributed_fizzbuzz/ebin
    $ erl -sname node2@localhost -setcookie fizz -pa $EBIN -noshell -detached
    $ erl -sname node3@localhost -setcookie fizz -pa $EBIN -noshell -detached
    $ erl -sname node1@localhost -setcookie fizz -pa $EBIN -noshell \
        -eval 'hit:distribute(),
               rpc:call(node2@localhost, init, stop, []),
               rpc:call(node3@localhost, init, stop, []),
               init:stop().'
