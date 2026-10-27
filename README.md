# misc

Code that did not find a place in other packages. Each directory below is a
separate dub subpackage and can be used on its own as `misc:<name>`.

## random

A set of random generators proposed for `std.random`. `predetermined` is the
seeded default, `Mt19937_64`; `truerandom` reads OS entropy (`getentropy`,
`getrandom`); `seededrandom` is a CSPRNG seeded from it, blocking or not;
`pseudorandom` is an insecure global generator with `setSeed`; `helper` adds
`rndGen` to fill a value from any of them inside a range pipeline.

## socket_stuff

`duplicateSocket` duplicates a socket descriptor: `dup` on Posix and
`WSADuplicateSocketW` on Windows. Also aliases `SocketException` as
`ConnectionException`, deprecated in favor of `SocketException`. Moved out of
dpq2.

## lockfree

`lockfree.list` is a push-only lock-free list for resource registries and
deferred destruction queues. Inserts come from any thread, a walk sees the
chain reachable from the head it loaded, and `drain` takes the whole chain with
one atomic exchange. Nodes live in the GC heap, so values keep their references
reachable. There is no removal, which rules out ABA. See `lockfree/PLAN.md`.
