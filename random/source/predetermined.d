///
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
alias Predetermined = Mt19937;
