///
module std.experimental.random.truerandom;

version (Posix)
{
    private extern(C) int getentropy(scope void* buf, size_t buflen) @system nothrow @nogc;

    //TODO: add this declaration to the druntime
    private extern(C) ptrdiff_t getrandom(scope void* buf, size_t buflen, uint flags) @system nothrow @nogc;
}
else version (Windows)
{
    // Windows random method is equal for all types of calls
    private void windowsRandom(scope ubyte[] result)
    {
        import core.sys.windows.bcrypt : BCryptGenRandom, BCRYPT_USE_SYSTEM_PREFERRED_RNG;
        import core.sys.windows.windef : HMODULE, PUCHAR, ULONG;
        import core.sys.windows.ntdef : NT_SUCCESS;

        const status = BCryptGenRandom(
            null, // hAlgorithm, null due to BCRYPT_USE_SYSTEM_PREFERRED_RNG used
            cast(PUCHAR) result.ptr,
            cast(ULONG) result.length,
            BCRYPT_USE_SYSTEM_PREFERRED_RNG
        );

        enforce(status == STATUS_SUCCESS);
    }
}

/// Blocks and waits if no enough entropy
void getTrueRandomBlocking(scope ubyte[] result)
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
        windowsRandom(result);
    }
}

/// Returns false if no enough entropy
bool getTrueRandom(scope ubyte[] result)
{
    import std.exception : enforce;

    version (Posix)
    {
        //TODO: add these declarations to the druntime
        version (linux)
        {
            enum GRND_NONBLOCK = 0x01;
            enum GRND_RANDOM = 0x02;
        }

        import core.stdc.errno : errno, EAGAIN;
        import std.exception : ErrnoException;

        assert(result.length <= 256);
        const status = getrandom(result.ptr, result.length, GRND_RANDOM | GRND_NONBLOCK);

        if (status == -1)
        {
            if(errno == EAGAIN)
                return false;

            throw new ErrnoException(null, errno);
        }

        return true;
    }
    else version (Windows)
    {
        windowsRandom(result);
        return true;
    }
}

unittest
{
    ubyte[24] buf;

    getTrueRandomBlocking(buf);
    getTrueRandom(buf);
}
