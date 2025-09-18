///
module std.experimental.random.truerandom;

version (Posix)
private extern(C) int getentropy(scope void* buf, size_t buflen) @system nothrow @nogc;

/// Blocks and waits if no enough entropy
void getTrueRandom(scope ubyte[] result)
{
    import std.exception : enforce;

    version (Posix)
    {
        //FIXME: https://github.com/dlang/dmd/pull/21836#issuecomment-3309075818
        //~ import core.sys.posix.unistd : getentropy;
        import std.exception : ErrnoException;

        assert(result.length <= 256);
        const status = getentropy(result.ptr, result.length);
        enforce!ErrnoException(status == 0);
    }
    else version (Windows)
    {
        import core.sys.windows.bcrypt : BCryptGenRandom, BCRYPT_USE_SYSTEM_PREFERRED_RNG;
        import core.sys.windows.windef : HMODULE, PUCHAR, ULONG;
        import core.sys.windows.ntdef : NT_SUCCESS;

        const status = BCryptGenRandom(
            null, // hAlgorithm, null due to BCRYPT_USE_SYSTEM_PREFERRED_RNG used
            /*cast(PUCHAR)*/ result.ptr,
            /*cast(ULONG)*/ result.length,
            BCRYPT_USE_SYSTEM_PREFERRED_RNG
        );

        enforce(status == STATUS_SUCCESS);
    }
    else
        static assert("Unsupported platform");
}

unittest
{
    ubyte[1024] buf;

    getTrueRandom(buf[0..5]);

    import std.stdio;
    buf.writeln;
}
