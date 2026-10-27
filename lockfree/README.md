`lockfree.list` is a push-only list for resource registries and deferred
destruction queues. Inserts come from any thread, a walk sees the chain
reachable from the head it loaded, and `drain` takes such a snapshot with one
atomic exchange. Nodes live in the GC heap, so values keep their references
reachable; removal never happens, which rules out ABA.

## Tests

Covered by `dub test --build=unittest-cov`, 100% of lines: head and tail
handles, empty handles, LIFO order, `alias this`, `break`, an exception during
value construction, GC reachability after `GC.collect`, a forced two-retry
insert, unique-value checks under contention, walks and drains racing with
inserts, 16-byte-aligned and large values, and rejection of types with a
destructor. `-O0` through `-O3` all pass.

- [ ] Weak memory ordering on a non-x86 target (ARM). No ARM host here; run the
      same tests on CI or under emulation when one is available.

The soak runs 2 million inserts from 8 threads while the main thread forces
`GC.collect`:

    ldc2 -O2 -unittest -main -d-version=LockFreeSoak source/lockfree/list.d

## Handles

`Elem` is a struct wrapping the node, so an empty handle is safe to pass around
and to call `next` on. Calling a method on a null class reference is undefined
behavior, and LDC with `-O2` miscompiled a whole unittest because of it.

## ABA

ABA needs a removal: a thread reads the head, the node is removed, its address
is reused, and a compare-and-swap on the stale value succeeds. `insertOne` never
dereferences the observed head, it only stores it as the new node's `next`, so
even a reused address still links the new node to the current chain. `drain` is
a single atomic exchange, so a pusher that read the old head fails and retries.
There is nothing to test here. An ABA test would need a removal operation, a
scheduler that stops a thread between the load and the CAS, and control over
address reuse, and it would still prove only the schedules it injects.
