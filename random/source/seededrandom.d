/// Cryptographically Secure Pseudorandom Number Generator (CSPRNG) seeded by TRNG
module std.experimental.random.seededrandom;

import std.exception : enforce;

version (Posix)
{
    import core.stdc.errno : errno, EAGAIN;
    import std.exception : ErrnoException;
    import std.experimental.random.truerandom : getrandom, maxRequestSize, posixRandom, GRND_NONBLOCK;
}
else version (Windows)
{
    import std.experimental.random.truerandom : maxRequestSize, windowsRandom;
}

/**
    Blocks if the seeding has not yet been initialized

    Note: the probability of blocking is negligible. Blocking is only
    possible during system startup, when the entropy pool may be even
    slightly unfilled.
*/
void getSeededRandomBlocking(scope ubyte[] result)
{
    version (Posix)
    {
        assert(result.length <= maxRequestSize, "");
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
