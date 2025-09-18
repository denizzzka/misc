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
