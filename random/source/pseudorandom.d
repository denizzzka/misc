///
module std.experimental.random.pseudorandom;

//~ version (Posix) {} else
//~ version (Windows) {} else
version = UseInternalPseudoRandom;

version (UseInternalPseudoRandom)
{
    import std.experimental.random.predetermined: Predetermined;

    private Predetermined presudoRng;

    ///
    void setSeed(ulong seed)
    {
        presudoRng = Predetermined(seed);
    }

    static this()
    {
        setSeed(4);
    }
}
else
{
    ///
    void setSeed(ulong seed)
    {
        // Does nothing if CSPRNG available
    }
}

///
version (UseInternalPseudoRandom)
void getPseudoRandom(scope ubyte[] result)
{
    import std.random: uniform;

    foreach (ref e; result)
    {
        e = presudoRng.uniform!ubyte;
        presudoRng.popFront();
    }
}
else
void getPseudoRandom(scope ubyte[] result)
{
    import std.experimental.random.seededrandom: getSeededRandomBlocking;

    getSeededRandomBlocking(result);
}

unittest
{
    ubyte[12] buf;

    setSeed(7);
    getPseudoRandom(buf);
}
