///
module std.experimental.random.seededrandom;

import std.exception : enforce;

version (Posix)
{
    import core.stdc.errno : errno, EAGAIN;
    import std.exception : ErrnoException;
    import std.experimental.random.truerandom : getrandom, posixRandom, GRND_NONBLOCK;
}
else version (Windows)
{
    import std.experimental.random.truerandom : windowsRandom;
}

/// Blocks if the seeding has not yet been initialized
void getSeededRandomBlocking(scope ubyte[] result)
{
    version (Posix)
    {
        assert(result.length <= 256);
        const len = getrandom(result.ptr, result.length, 0);
        enforce!ErrnoException(len != -1);
        assert(len == result.length);
    }
    else version (Windows)
    {
        windowsRandom(result);
    }
}

/// Returns false if the seeding has not yet been initialized
bool getSeededRandom(scope ubyte[] result)
{
    version (Posix)
    {
        return posixRandom(result, GRND_NONBLOCK);
    }
    else version (Windows)
    {
        windowsRandom(result);
        return true;
    }
}

/// Throws if the seeding has not yet been initialized
void getSeededRandomEx(scope ubyte[] result)
{
    //TODO: introduce new exception class?
    enforce(getSeededRandom(result) == true);
}

unittest
{
    ubyte[24] buf;

    getSeededRandomBlocking(buf);
    getSeededRandom(buf);
    getSeededRandomEx(buf);
}

/// Example
unittest
{
    import std.range;
    import std.stdio: writeln;

    int[] arr = generate!((){
        union U
        {
            int i;
            ubyte[uint.sizeof] b;
        }

        U ret;
        getSeededRandomBlocking(ret.b);
        return ret.i;
    }).take(5).array;

    //~ arr.writeln;
}

//TODO: move to helpers module?
auto helper(T, alias Func = getSeededRandomBlocking)()
{
    // Posix restriction:
    // TODO: add for Windows, MacOS, etc
    enum maxRequestSize = 255;

    union U
    {
        T val;
        ubyte[T.sizeof] buf;
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

/// Example
unittest
{
    import std.range;
    import std.stdio: writeln;

    helper!int.writeln;

    struct S
    {
        int[1024] arr;
    }

    generate!(() => helper!S)
        .take(3)
        .array;

    import std.experimental.random.truerandom: getTrueRandomEx;

    int[] arr = generate!(() => helper!(int, getTrueRandomEx))
        .take(5)
        .array;

    arr.writeln;
}
