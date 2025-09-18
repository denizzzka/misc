///
module std.experimental.random.truerandom;

version (D_Exceptions)
{
    //~ void trueRandomEx(ref ubyte[] result); // throws if no enough entropy
}

// BetterC compatible:

private extern(C) int getentropy(scope void* buf, size_t buflen) @system;

/// Blocks and waits if no enough entropy
void getTrueRandom(ubyte[] result) @trusted
{
    version (Windows)
    {
    }
    else version (Posix)
    {
        import std.exception : enforce, ErrnoException;

        assert(result.length <= 256);
        const status = getentropy(result.ptr, result.length);
        enforce!ErrnoException(status == 0);
    }
}

unittest
{
    ubyte[1024] buf;

    getTrueRandom(buf[0..5]);

    import std.stdio;
    buf.writeln;
}
