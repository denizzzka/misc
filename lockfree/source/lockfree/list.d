module lockfree.list;

import core.atomic: atomicExchange, atomicLoad, cas;
import std.traits: hasElaborateDestructor;

/// Push-only list shared between threads.
/// A walk sees the chain reachable from the head it loaded, so it can run while
/// other threads insert; `drain` takes such a snapshot with one exchange.
/// Nodes live in the GC heap, so values keep their references reachable.
struct LockFreeList(T)
{
    static assert(!hasElaborateDestructor!T,
        "LockFreeList never destroys elements; use a value without a destructor");

    private final class Node
    {
        T value;
        Node next;
    }

    /// Handle to an inserted element; keeps its node reachable.
    struct Elem
    {
        private Node node;

        ref T value()
        {
            assert(node !is null, "empty LockFreeList element");
            return node.value;
        }

        alias value this;

        /// Older element, or an empty handle at the end of the chain.
        Elem next() => node is null ? Elem.init : Elem(node.next);

        bool opCast(T : bool)() const => node !is null;
    }

    private shared(Node) head;

    version (unittest)
    {
        /// Runs before every CAS attempt; lets a test force a retry.
        private void delegate() beforeCas;
    }

    /// Builds an element with `dg`, pushes it and returns its handle.
    Elem insertOne(void delegate(ref T) dg)
    {
        auto node = new Node;
        dg(node.value);

        while(true)
        {
            auto old = cast(Node) atomicLoad(head);
            node.next = old;

            version (unittest)
            {
                if(beforeCas !is null)
                    beforeCas();
            }

            if(cas(&head, cast(shared) old, cast(shared) node))
                return Elem(node);
        }
    }

    /// Pushes a copy of `value`.
    Elem insert(T value)
    {
        return insertOne((ref T v) { v = value; });
    }

    /// Removes the elements present at the moment of the call and returns them
    /// as a chain. Inserts that race with it land either here or in the list.
    Elem drain()
    {
        return Elem(cast(Node) atomicExchange(&head, cast(shared) null));
    }

    /// True when no element is left.
    bool empty() const => cast(Node) atomicLoad(head) is null;

    /// Number of elements. O(n), meant for tests and statistics.
    size_t length() const
    {
        size_t n;
        for(auto e = cast(Node) atomicLoad(head); e !is null; e = e.next)
            ++n;
        return n;
    }

    /// Walks the chain reachable from the head at the moment of the call,
    /// newest first.
    int opApply(scope int delegate(ref T) dg)
    {
        for(auto e = cast(Node) atomicLoad(head); e !is null; e = e.next)
            if(auto r = dg(e.value))
                return r;
        return 0;
    }
}

unittest
{
    LockFreeList!int list;
    assert(list.empty);
    assert(list.length == 0);
    assert(!list.drain);

    auto first = list.insertOne((ref int v) { v = 1; });
    auto second = list.insert(2);
    auto third = list.insert(3);

    assert(!list.empty);
    assert(list.length == 3);
    assert(first.value == 1); // the handle survives later inserts
    assert(third.next is second);
    assert(third.next.value == 2);
    assert(third.next.next.value == 1);
    assert(!third.next.next.next);
    assert(!first.next); // the oldest element is the tail

    first.value = 10;
    assert(first.value == 10); // the handle refers to the stored value

    static int takeInt(int v) => v;
    assert(takeInt(first) == 10); // alias this forwards the element as T

    // newest first
    int[] order;
    foreach(ref v; list)
        order ~= v;
    assert(order == [3, 2, 10]);

    // break stops the walk
    size_t seen;
    foreach(ref v; list)
    {
        ++seen;
        if(seen == 2)
            break;
    }
    assert(seen == 2);

    // an empty handle is false and its next is empty
    LockFreeList!int.Elem nobody;
    assert(!nobody);
    assert(!nobody.next);

    auto chain = list.drain();
    assert(list.empty);
    assert(list.length == 0);
    assert(!list.drain);

    size_t drained;
    for(auto e = chain; e; e = e.next)
        ++drained;
    assert(drained == 3);
    assert(chain.next.next.value == 10); // drained nodes stay reachable

    // the list is reusable after a drain
    list.insert(4);
    assert(list.length == 1);
    assert(list.drain.value == 4);
    assert(list.empty);
}

unittest
{
    // Force CAS retries: the hook pushes a competing node between the head load
    // and the CAS, so the outer insert has to retry.
    LockFreeList!int list;

    size_t injected;
    bool insideHook;

    list.beforeCas = {
        if(insideHook)
            return;

        if(injected == 2)
        {
            list.beforeCas = null;
            return;
        }

        insideHook = true;
        scope(exit) insideHook = false;

        list.insert(cast(int) ++injected);
    };

    auto pushed = list.insert(9);

    assert(injected == 2);
    assert(list.beforeCas is null);
    assert(list.length == 3);
    assert(pushed.value == 9);

    int[] order;
    foreach(ref v; list)
        order ~= v;
    assert(order == [9, 2, 1]);

    auto chain = list.drain();
    assert(chain.value == 9);
    assert(chain.next.value == 2);
    assert(chain.next.next.value == 1);
}

private struct ThrowingValue
{
    this(int)
    {
        throw new Exception("constructor failed");
    }
}

unittest
{
    import std.exception: assertThrown;

    LockFreeList!ThrowingValue list;
    assertThrown(list.insertOne((ref ThrowingValue v) { v = ThrowingValue(1); }));
    assert(list.empty);
    assert(list.length == 0);
}

private __gshared LockFreeList!(int[]) collectedList;

unittest
{
    import core.memory: GC;

    collectedList.drain();
    collectedList.insert([7, 8, 9]);

    GC.collect();

    int[] found;
    foreach(ref v; collectedList)
        found = v;
    assert(found == [7, 8, 9]);

    collectedList.drain();
}

private struct AlignedValue
{
    align(16) long payload;
}

private struct BigValue
{
    long[16] payload;
}

unittest
{
    LockFreeList!AlignedValue alignedList;
    auto aligned = alignedList.insert(AlignedValue(1));
    assert((cast(size_t) &aligned.value()) % 16 == 0);
    assert(aligned.value.payload == 1);

    LockFreeList!BigValue bigList;
    BigValue big;
    big.payload[0] = 42;
    big.payload[$ - 1] = 7;

    auto stored = bigList.insert(big);
    assert(stored.value.payload[0] == 42);
    assert(stored.value.payload[$ - 1] == 7);
}

private struct DestructiveValue
{
    ~this() {}
}

// Elements are never destroyed, so such a type must not be accepted.
static assert(!__traits(compiles, LockFreeList!DestructiveValue));

private __gshared LockFreeList!int walkedList;

unittest
{
    import core.atomic: atomicLoad, atomicOp;
    import core.thread: Thread;

    enum writerCount = 4;
    enum perWriter = 2000;
    enum total = writerCount * perWriter;

    walkedList.drain();

    shared size_t finished;

    Thread[] writers;

    void startWriter(int id)
    {
        writers ~= new Thread({
            foreach(i; 0 .. perWriter)
            {
                walkedList.insert(id * perWriter + i);
                if((i & 63) == 0)
                    Thread.yield();
            }
            atomicOp!"+="(finished, 1);
        }).start();
    }

    foreach(t; 0 .. writerCount)
        startWriter(cast(int) t);

    size_t visits;
    do
    {
        // The walk follows the chain reachable from the head it loaded, so it is
        // a snapshot and can run while the writers insert.
        foreach(ref v; walkedList)
        {
            assert(v >= 0 && v < total);
            ++visits;
        }
        Thread.yield();
    }
    while(atomicLoad(finished) < writerCount);

    foreach(t; writers)
        t.join();

    assert(visits > 0);
    assert(walkedList.length == total);

    bool[] seen;
    seen.length = total;
    foreach(ref v; walkedList)
    {
        assert(!seen[v]);
        seen[v] = true;
    }
    foreach(b; seen)
        assert(b);

    walkedList.drain();
}

private __gshared LockFreeList!ulong drainedList;

unittest
{
    import core.atomic: atomicLoad, atomicOp;
    import core.thread: Thread;

    enum writerCount = 4;
    enum perWriter = 4000;
    enum total = writerCount * perWriter;

    drainedList.drain();

    shared size_t finished;

    Thread[] writers;

    void startWriter(int id)
    {
        writers ~= new Thread({
            foreach(i; 0 .. perWriter)
                drainedList.insert(cast(ulong) (id * perWriter + i));
            atomicOp!"+="(finished, 1);
        }).start();
    }

    foreach(t; 0 .. writerCount)
        startWriter(cast(int) t);

    size_t taken;
    ulong sum;

    void take(LockFreeList!ulong.Elem chain)
    {
        for(auto e = chain; e; e = e.next)
        {
            ++taken;
            sum += e.value;
        }
    }

    while(true)
    {
        take(drainedList.drain());

        if(atomicLoad(finished) == writerCount)
        {
            take(drainedList.drain());
            break;
        }

        Thread.yield();
    }

    foreach(t; writers)
        t.join();

    assert(taken == total);
    assert(sum == cast(ulong) total * (total - 1) / 2);
    assert(drainedList.empty);
}

private struct ConcurrentRegistry
{
    LockFreeList!ulong handles;
    LockFreeList!(int[]) arrays;
}

private __gshared ConcurrentRegistry concurrentRegistry;

unittest
{
    import core.memory: GC;
    import core.thread: Thread;

    enum threadCount = 4;
    enum perThread = 2000;
    enum total = threadCount * perThread;

    concurrentRegistry.handles.drain();
    concurrentRegistry.arrays.drain();

    Thread[] workers;

    void startWorker(int id)
    {
        workers ~= new Thread({
            foreach(i; 0 .. perThread)
            {
                concurrentRegistry.handles.insert(cast(ulong) (id * perThread + i));
                concurrentRegistry.arrays.insert([cast(int) i, 1]);
            }
        }).start();
    }

    foreach(t; 0 .. threadCount)
        startWorker(cast(int) t);

    foreach(t; workers)
        t.join();

    GC.collect();

    assert(concurrentRegistry.handles.length == total);
    assert(concurrentRegistry.arrays.length == total);

    // every value appears exactly once
    bool[] seen;
    seen.length = total;
    foreach(ref v; concurrentRegistry.handles)
    {
        assert(!seen[cast(size_t) v]);
        seen[cast(size_t) v] = true;
    }
    foreach(b; seen)
        assert(b);

    size_t lengths;
    foreach(ref v; concurrentRegistry.arrays)
        lengths += v.length;
    assert(lengths == total * 2);

    concurrentRegistry.handles.drain();
    concurrentRegistry.arrays.drain();
}

version (LockFreeSoak)
{
    private __gshared LockFreeList!ulong soakList;

    unittest
    {
        import core.atomic: atomicLoad, atomicOp;
        import core.memory: GC;
        import core.thread: Thread;
        import core.time: dur;

        enum writerCount = 8;
        enum perWriter = 250_000;
        enum total = writerCount * perWriter;

        soakList.drain();

        shared size_t finished;

        Thread[] writers;

        void startWriter(int id)
        {
            writers ~= new Thread({
                foreach(i; 0 .. perWriter)
                    soakList.insert(cast(ulong) (id * perWriter + i));
                atomicOp!"+="(finished, 1);
            }).start();
        }

        foreach(t; 0 .. writerCount)
            startWriter(cast(int) t);

        while(atomicLoad(finished) < writerCount)
        {
            Thread.sleep(dur!"msecs"(5));
            GC.collect();
        }

        foreach(t; writers)
            t.join();

        assert(soakList.length == total);

        ulong sum;
        foreach(ref v; soakList)
            sum += v;
        assert(sum == cast(ulong) total * (total - 1) / 2);

        soakList.drain();
    }
}
