///
module std.experimental.random.pseudorandom;

//~ version = UseInternalPseudoRandom;

///
version (UseInternalPseudoRandom)
void getPseudoRandom(scope ubyte[] result)
{
    static assert(false, "Not implemented");
}
else
void getPseudoRandom(scope ubyte[] result)
{
    import std.experimental.random.seededrandom: getSeededRandomBlocking;

    getSeededRandomBlocking(result);
}

unittest
{
    ubyte[240] buf;

    getPseudoRandom(buf);
}
