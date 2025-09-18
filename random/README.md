# std.experimental.random

> TL;DR: You need to use `std.random.seededrandom.getSeededRandomBlocking`

### Implementation based on [this forum post](https://forum.dlang.org/post/yklxasqnjhslewtkrejv@forum.dlang.org)

I don't like the way the module `std.random` is designed

From a software side we have three types of ~random numbers sources:

1. Hardware (or environmental) "true" noise.
The most reliable source, which may not be that fast, i.e. it may be emptied in some cases, so it can be blocking and non-blocking in block devices terms.
This is exacatly what provided by `/dev/random` in Linux. It should also be noted that this random source type does not exist on all platforms.

2. Based on hardware noise (described in 1 above) seeded pseudo-random sequence.
Less (but still) reliable because it extrapolates a true random number using a deterministic algorithm (like described in 3 below). Suitable for generating large volumes of numbers.
This is exacatly what provided by `/dev/urandom` in Linux. Again, not all platforms providing it.

3. Pre-determined pseudorandom sequences based on some predictable algorithm.
Also good for getting large amounts of numbers and fast, but it strictly can't be used for cryptography etc. Its advantage is that it is always available in all systems since (at worst) it is just a mathematical function.

I think if we save users from deepening into details this will only go to the benefit of security. So, my suggestion:

1. Do not deal with "entropy" as a separate entity. At the application programming level we usually have one source of true entropy. (If this is not so please correct me.) No need to make ambitious interfaces describing the theoretical diversity of RNGs. The "entropy" word can be excluded from the API description completely - entropy is simply good quality random numbers.

2. Completely exclude "seeding" concept: this is a source of [potential issues](https://github.com/dlang/phobos/pull/10865). Seeding can be encapsulated inside of the CSPRNG generator (see 2 above) if needed. (But in fact, almost all operating systems have implemented this for us: `/dev/urandom` and so one)

In fact, you know exactly what amount and quality of random bytes you want to get at some point of your code. And, for example, if system does not provides true RNG needed by you, then let the corresponding function be totally unavailable for compilation and leads to compile time error. Then you can't accidentally build your neat designed software with weak predictable RNG.

It follows from this that it is necessary to provide only four points for obtaining random numbers, all without the need for any combining of them by users. (My suggestion is place each of it in dedicated `std.random.*` module)

1. `std.random.truerandom`, TRNG: implemented as OS/hardware call if system provides hardware (or environmental) random number generator. Suitable for encryption key generation, etc.
If there is no random number generator in the system, then these functions will not be available and the compilation may end with the error!
(Modern operating systems often disguise CSPRNG as TRNG, but that doesn't matter to us at this abstraction level.)

2. `std.random.seededrandom`: function(s) implementing CSPRNG, either by OS call (for Linux/Windows/Mac) or by some another TRNG call + PseudoRandom (on baremetal platforms).
Almost does not blocks and not throws. Does not exist if there is no internal system TRNG avalable, because implamentation should use seed value.
So, again: if there is no true random number generator in the system, then these functions will not be available and the compilation may fail.
CSPRNG are pretty good random numbers for general purpose like UUID generation.

3. `std.random.pseudorandom`: not for cryptography at all. Name was specifically chosen so that the user would clearly see the "pseudo" prefix.
Suitable for drawing a starry sky in a retro games or so one. Internally calls `std.random.seededrandom` if exists or `uses std.random.predetermined` (4) with seed value if seededrandom doesn't exist.
Guaranteed to exist on all platforms.

4. `std.random.predetermined`: functions implementing pseudorandom number generators (PRNG). Mostly for internal use, but sometimes users may want to get guaranteed repeatability of pseudorandom sequences.

That's all, and nothing superfluous! I.e., if you do not use something, it does not creates any global variables, etc. From the point of view of the user, seems, everything is also simple and clear.
