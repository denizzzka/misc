/// (Insecure) Pseudorandom Number Generator (PRNG)
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

version (UseInternalPseudoRandom)
unittest
{
    ubyte[16] a;
    ubyte[16] b;

    setSeed(7);
    getPseudoRandom(a);
    setSeed(7);
    getPseudoRandom(b);
    assert(a == b);

    setSeed(8);
    getPseudoRandom(b);
    assert(a != b);

    ubyte[1] one;
    setSeed(7);
    getPseudoRandom(one);
}

unittest
{
    ubyte[0] empty;
    setSeed(1);
    getPseudoRandom(empty);
}

unittest
{
    ubyte[100] big;
    setSeed(7);
    getPseudoRandom(big);
    assert(big.length == 100);
}
