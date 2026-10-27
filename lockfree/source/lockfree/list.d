module lockfree.list;

import core.atomic: atomicExchange, atomicLoad, cas;

/// Push-only list shared between threads.
/// Nodes live in the GC heap, so values keep their references reachable.
/// Walking is safe only after all writers have stopped.
struct LockFreeList(T)
{
    /// One list entry, also the handle returned by `insertOne`.
    final class Node
    {
        T value;
        private Node _next;

        /// Older element, or null at the end of the chain.
        Node next() => this is null ? null : _next;

        ref T getValue()
        {
            assert(this !is null, "empty LockFreeList element");
            return value;
        }

        alias getValue this;
    }

    alias Elem = Node;

    private shared(Node) head;

    version (unittest)
    {
        /// Runs before every CAS attempt; lets a test force a retry.
        private void delegate() beforeCas;
    }

    /// Builds an element with `dg`, pushes it and returns its node.
    Elem insertOne(void delegate(ref T) dg)
    {
        auto node = new Node;
        dg(node.value);

        while(true)
        {
            auto old = cast(Node) atomicLoad(head);
            node._next = old;

            version (unittest)
            {
                if(beforeCas !is null)
                    beforeCas();
            }

            if(cas(&head, cast(shared) old, cast(shared) node))
                return node;
        }
    }

    /// Pushes a copy of `value`.
    Elem insert(T value)
    {
        return insertOne((ref T v) { v = value; });
    }

    /// Removes every element and returns the chain it formed.
    /// The caller must be the only thread touching the list while this runs.
    Elem drain()
    {
        return cast(Node) atomicExchange(&head, cast(shared) null);
    }

    /// True when no element is left.
    bool empty() const => cast(Node) atomicLoad(head) is null;

    /// Number of elements. O(n), meant for tests and statistics.
    size_t length() const
    {
        size_t n;
        for(auto e = cast(Node) atomicLoad(head); e !is null; e = e._next)
            ++n;
        return n;
    }

    /// Walks the list from the newest element to the oldest.
    int opApply(scope int delegate(ref T) dg)
    {
        for(auto e = cast(Node) atomicLoad(head); e !is null; e = e._next)
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
    assert(list.drain is null);

    auto first = list.insertOne((ref int v) { v = 1; });
    auto second = list.insert(2);
    auto third = list.insert(3);

    assert(!list.empty);
    assert(list.length == 3);
    assert(first.value == 1); // the handle survives later inserts
    assert(third.next is second);
    assert(third.next.value == 2);
    assert(third.next.next.value == 1);
    assert(third.next.next.next is null);
    assert(first.next is null); // the oldest element is the tail

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

    // an empty handle is null and its next is null
    LockFreeList!int.Elem nobody;
    assert(nobody is null);
    assert(nobody.next is null);

    auto chain = list.drain();
    assert(list.empty);
    assert(list.length == 0);
    assert(list.drain is null);

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

    concurrentRegistry.handles.drain();
    concurrentRegistry.arrays.drain();

    Thread[] workers;
    foreach(t; 0 .. threadCount)
        workers ~= new Thread({
            foreach(i; 0 .. perThread)
            {
                concurrentRegistry.handles.insert(cast(ulong) i);
                concurrentRegistry.arrays.insert([cast(int) i, 1]);
            }
        }).start();

    foreach(t; workers)
        t.join();

    GC.collect();

    assert(concurrentRegistry.handles.length == threadCount * perThread);
    assert(concurrentRegistry.arrays.length == threadCount * perThread);

    ulong sum;
    foreach(ref v; concurrentRegistry.handles)
        sum += v;
    assert(sum == threadCount * (perThread - 1) * perThread / 2);

    size_t lengths;
    foreach(ref v; concurrentRegistry.arrays)
        lengths += v.length;
    assert(lengths == threadCount * perThread * 2);

    concurrentRegistry.handles.drain();
    concurrentRegistry.arrays.drain();
}
