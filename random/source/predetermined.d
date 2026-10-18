/// Pseudorandom Number Generator (PRNG) backend functions
module std.experimental.random.predetermined;

public import std.random:
    MersenneTwisterEngine,
    Mt19937,
    Mt19937_64;

/**
The "default", "favorite", "suggested" CSPRNG type on the current
platform. It is an alias for one of the previously-defined generators.
You may want to use it if (1) you need to generate some nice random
numbers, and (2) you don't care for the minutiae of the method being
used.
 */
alias Predetermined = Mt19937_64;

unittest
{
    import std.random : isUniformRNG, uniform;
    static assert(isUniformRNG!Predetermined);
    static assert(is(Predetermined == Mt19937_64));

    auto a = Predetermined(42);
    auto b = Predetermined(42);
    foreach (_; 0 .. 100)
        assert(a.uniform!uint == b.uniform!uint);

    auto c = Predetermined(43);
    assert(c.uniform!uint != a.uniform!uint);
}
