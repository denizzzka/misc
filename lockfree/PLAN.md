# Plan

`lockfree.list` is a push-only list for resource registries and deferred
destruction queues: inserts come from any thread, iteration happens after the
writers stop, and `drain` moves the whole chain out at a quiescent point. Nodes
live in the GC heap, so values keep their references reachable; removal never
happens, which rules out ABA.

Checkboxes track progress: `[ ]` is open, `[x]` is done.

## Tests

Covered by `dub test --build=unittest-cov`, 100% of lines: empty list, insert
through a delegate and through a value, handle lifetime, chain order, `alias
this`, iteration order and `break`, empty handles, `drain` and reuse, an
exception during value construction, GC reachability after `GC.collect`, a
forced two-retry insert, and 4 x 2000 concurrent inserts into two shared lists.

- [ ] Walking under concurrent inserts. A walk follows the chain reachable from
      the head it loaded, and `next` never changes after publication, so this
      should already work; the module docs forbid it.
- [ ] `drain` under concurrent inserts. It is one atomic exchange: a pusher
      either lands in the drained chain or in the new one, and a pusher that
      read the old head fails its CAS and retries. Should already work; the
      module docs forbid it.
- [ ] Linearizability under contention: counts and sums catch lost and
      duplicated nodes, not every interleaving.
- [ ] Soak with millions of operations and a random `GC.collect` while workers
      push.
- [ ] Weak memory ordering on a non-x86 target (ARM).
- [ ] Large `T`, alignment, and a type with a destructor.
- [ ] Allocation failure: `new Node` throws and the list stays unchanged.

## Contract

Walking and draining during inserts are expected to be safe, but the module docs
still say the writers must stop. Either promise the snapshot behavior, document
it and test it, or keep the restriction and reject it explicitly.

## ABA

ABA needs a removal: a thread reads the head, the node is removed, its address
is reused, and a compare-and-swap on the stale value succeeds. `insertOne` never
dereferences the observed head, it only stores it as the new node's `next`, so
even a reused address still links the new node to the current chain. `drain` is
a single atomic exchange, so a pusher that read the old head fails and retries.
There is nothing to test here. An ABA test would need a removal operation, a
scheduler that stops a thread between the load and the CAS, and control over
address reuse, and it would still prove only the schedules it injects.
