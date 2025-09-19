///
module std.experimental.random.helper;

import std.experimental.random.truerandom: maxRequestSize;
import std.experimental.random.seededrandom: getSeededRandomBlocking;

/**
Wraps random generator function to convenient usage with ranges pipelines

It takes into account the maximum possible buffer size and
transparently makes multiple generator calls if necessary.

Returning: generated value of the requested type
*/
T rndGen(T, alias Func = getSeededRandomBlocking)()
{
    union U
    {
        T val; //=void
        ubyte[T.sizeof] buf; //=void
    }
    U u; //=void

    static if(T.sizeof <= maxRequestSize)
    {
        Func(u.buf);
        return u.val;
    }

    ubyte[maxRequestSize] buf;

    size_t i;
    size_t left; //=void
    do
    {
        left = T.sizeof - i;

        const beRequested = (left < buf.length)
            ? left
            : buf.length;

        const next = i + beRequested;
        Func(u.buf[i .. next]);

        i = next;
    }
    while(left != 0);
    assert(left == 0);

    return u.val;
}

import std.range;

///
unittest
{
    const int one_rnd_value = rndGen!int;
}

///
unittest
{
    struct S
    {
        int[1024] arr;
    }

    const s_array = generate!(() => rndGen!S)
        .take(3)
        .array;

    import std.experimental.random.truerandom: getTrueRandomEx;

    int[] arr = generate!(() => rndGen!(int, getTrueRandomEx))
        .take(5)
        .array;

    auto arr_static = generate!(() => rndGen!(int[500]))
        .take(10)
        .array;
}
