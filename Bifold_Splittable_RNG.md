---
marp: true
math: mathjax
theme: custom
header: Bifold Splittable RNG
paginate: true
---
<!-- _class: lead -->
<!-- _footer: JuliaCon 2025 -->
<!-- _paginate: false -->

# Bifold

## A collision-resistant, splitable RNG for structured parallelism

*Stefan Karpinski*

https://JuliaHub.com

---
<!-- _class: default -->

# Pop Quiz

What does this code print?

```julia
using Random
Random.seed!(123)
show(rand(UInt64))
```

Trick question! It depends on the version of Julia

One thing we did right long ago was to adamantly insist that default RNG output is not stable across minor Julia versions

---
# Historical Answers

| versions       | output               | algorithm        | seeding |
|:--------------:|:--------------------:|:----------------:|:-------:|
| ≤ 1.5          | `0xbe6f0eacf58ebf12` | Mersenne Twister | naive   |
| = 1.6          | `0xf5450eab0f9f1b7f` | Mersenne Twister | SHA256  |
| ≥ 1.7          | `0x856e446e0c6a972a` | Xoshiro256++     | SHA256  |

Note: we used dSFMT, a variant of classic Mersenne Twister

---
# Why did we change RNGs?

Mersenne Twister is not a great RNG by modern standards

- Huge state: 2496 bytes
- Period of $2^{19937} − 1$ is excessive
- Fails many statistical tests:
  - TestU01 BigCrush
  - low bits have poor quality

---
# Why Change RNGs?

Xoshiro256++ is one of the best general purpose, modern RNGs

- Small state: 32 bytes
- Period of $2^{256} - 1$ is plenty
- Passes statistical test suites
  - low bits are slightly weak but better than MT

---
# Even more significantly...

Xoshiro256's compact size enables task-local RNG state

- Before: shared global RNG state
  - requires locks — boo, slooow
  - RNG sequence depends on *global* sampling order
- After: each task has its own RNG state
  - no locks — yay! fast
  - RNG sequence depends only on task tree shape

---
# Reproducability

```julia
function order_test(parent_sleep, child_sleep)
    Random.seed!(0)
    @sync begin
        @async begin
            sleep(child_sleep)
            println("child:  $(repr(rand(UInt64)))")
        end
        sleep(parent_sleep)
        println("parent: $(repr(rand(UInt64)))")
    end
end
```

---
# Julia 1.6

Shared global RNG:

```julia
julia> order_test(0, 1)
parent: 0xbfad144bf7250b28
child:  0x21be0e591a3b69ea

julia> order_test(1, 0)
child:  0xbfad144bf7250b28
parent: 0x21be0e591a3b69ea
```

---
# Julia 1.7

Per-task RNG:

```julia
julia> order_test(0, 1)
parent: 0xa95f73054eb51179
child:  0x557173e70ae5a5ee

julia> order_test(1, 0)
child:  0x557173e70ae5a5ee
parent: 0xa95f73054eb51179
```

---
# A Huge Improvement

Many thanks to [Chet Hega](https://github.com/chethega) for the PR that originally implemented this!

- Small state
- Better RNG
- Faster RNG + no locking = _much faster_
- Reproducible
  - deterministic based only on task tree shape

---
# One Minor Annoyance

In Julia 1.7-1.9:

```julia
julia> begin
           Random.seed!(0)
           println(repr(rand(UInt64)))
           println(repr(rand(UInt64)))
       end
0x67dbeba77c5b608f
0x118c381a04770c92
```

---
# One Minor Annoyance

In Julia 1.7-1.9:

```julia
julia> begin
           Random.seed!(0)
           println(repr(rand(UInt64)))
           @async nothing # <= this can't matter, right?
           println(repr(rand(UInt64)))
       end
0x67dbeba77c5b608f
0x1dc7a124563dedbd # <= different value!
```

---
# The Problem

In Julia 1.7-1.9:

- Merely spawning a child task changes the parent RNG
- Doesn't matter if the child uses the RNG or not
- We shouldn't care if code we call spawns a task or not
  - see [*What Color is Your Function?*](https://journal.stuffwithstuff.com/2015/02/01/what-color-is-your-function/)
  - that's about types, but it's the same principle

---
# Why does this happen?

When forking a task, child's RNG needs to be seeded
- Can't just copy parent state
- Parent & child would produce same values

In 1.7-1.9 the child is seeded by sampling from the parent RNG
- This modifies the parent RNG, changing its RNG sequence
  - uses RNG four times—once per word of Xoshiro256 state

---
# These behave the same (1.7-1.9)

```julia
Random.seed!(0)
println(repr(rand(UInt64)))
@async nothing              # uses RNG 4 times
println(repr(rand(UInt64)))
```

```julia
Random.seed!(0)
println(repr(rand(UInt64)))
[rand(UInt64) for _ = 1:4]  # call RNG 4 times
println(repr(rand(UInt64)))
```

---
# To The Literature!

DotMix (2012): *Deterministic Parallel Random-Number Generation for Dynamic-Multithreading Platforms*
- by Charles Leiserson, Tao Schardl, Jim Sukha
- for MIT Cilk parallel runtime

SplitMix (2014): *Fast Splittable Pseudorandom Number Generators*
- by Guy Steele Jr, Doug Lea, Christine Flood
- for Oracle's Java JDK8

---
# DotMix

Concept: "pedigree" vector of a task
- Root task has pedigree $\langle \rangle$
- If parent has pedigree $\langle k_1, k_2, ..., k_{d-1} \rangle$
- Its children are at depth $d$ in the task tree
- The $k_d$th child has pedigree $\langle k_1, k_2, ..., k_{d-1}, k_d \rangle$

Every prefix of a task's pedigree is the pedigree of an ancestor
- Can zero-extend pedigree vectors to match lengths

---
# DotMix

Core idea:
- Compute a dot product of a task's pedigree with random weights
- Can prove dot product collisions have probability near $1/2^{64}$
- Apply bijective, non-linear "finalizer" based on MurmurHash
- Finalized value is used to seed a main RNG (per-task)

---
# DotMix: details

The dot product of a pedigree vector looks like this:
$$
\chi\langle k_1, \dots, k_d \rangle = \sum_{i=1}^d w_i k_i \pmod p
$$
- $p$ is a prime modulus
  - necessary for proof of collision resistance
- They use $p = 2^{64} - 59$
  - complicates the implementation a fair bit

---
# DotMix: proof

Suppose two different tasks have the same $\chi$ value:
$$
\sum_{i=1}^d w_i k_i = \sum_{i=1}^d w_i k_i'  \pmod p
$$
Let $j$ be some coordinate where $k_j ≠ k_j'$
$$\begin{align}
w_j (k_j - k_j') = \delta &\pmod p \\
w_j = \delta (k_j - k_j')^{-1} &\pmod p
\end{align}$$

---
# SplitMix

### So funny story...

Authors spend _a lot of time_ an an optimized version of DotMix

- I thought that this optimized version was SplitMix — it's not
- Then the paper just throws up its hands and does something else

In my defense, they spend the first _12 out of 20_ pages on DotMix

---
# What SplitMix actually is

$s$ is the main RNG state; $γ$ is a per-task constant
```julia
advance(s::UInt64) = s += γ # <= very simple state transition

function gen_value(s::UInt64)
    s ⊻= s >> 33; s *= 0xff51afd7ed558ccd
    s ⊻= s >> 33; s *= 0xc4ceb9fe1a85ec53
    s ⊻= s >> 33
end
```
State transition is very weak, relies entirely on output function

---
# SplitMix: splitting

```julia
s = advance(s); s′ = gen_value(s) # <= child state
s = advance(s); γ′ = gen_gamma(s) # <= child gamma
```

```julia
function gen_gamma(s::UInt64)
    s ⊻= s >> 30; s *= 0xbf58476d1ce4e5b9
    s ⊻= s >> 27; s *= 0x94d049bb133111eb
    s ⊻= s >> 31; s |= 0x0000000000000001
    s ⊻= ((s ⊻ (s >>> 1)) ≥ 24) * 0xaaaaaaaaaaaaaaaa
end
```

---
# SplitMix: splitting

Almost what we're doing in Julia 1.7-1.9

- Both sample parent to set child state
- SplitMix is parameterized by per-task $γ$

Cool idea:
- Even if tasks have an RNG state collision
- As long as $γ$ values are different, it's still fine

---
# Auxiliary RNG or not?

- DotMix is explicitly intended as an _auxiliary RNG_
  - used to seed main RNG on task fork, not to generate samples
- SplitMix can be used as main RNG _and_ to fork children
  - but if you do that, then forking changes the parent RNG stream

---
# Auxiliary RNG or not?

We need to have auxiliary RNG state:
- By _requirement_, forking children must not change main RNG state
- But _something_ must change or every child task would be identical

So we _need_ to have auxiliary RNG state outside of main RNG

---
# SplitMix as auxiliary RNG?

If we used SplitMix for this, it would add 128 bits of aux RNG state

- This is _per task object_, so we really want to keep it minimal
- More than 64 bits of aux RNG state seems like too much

We don't need SplitMix's ability to generate _and_ split

- Should use all aux RNG bits for splitting, none for generation
- DotMix does this — and it has collision resistance proof

---
# Optimized DotMix (SplitMix paper)

Main optimization Steele _et al._ make to DotMix:

- Task stores dot product of previously forked child
- Starts with parent's own dot product
- When forking next child, just add $w_d$ ($d$ is tree depth)
- New dot product saved in both parent and child 

---
# Optimized DotMix (SplitMix paper)

Other optimizations:

- Use prime modulus of $p = 2^{64} + 13$ with some cleverness
- Use cheaper non-linear, bijective finalizer

Their improved DotMix is a great start

- We're going to see if we can improve it even more...

---
# Improving DotMix further

Prime modulus arithmetic is slow and complicated

- A lot of effort is put into optimizing it in both papers
- Even better if we could just use native arithmetic

---
# Improving DotMix further

Why do we need a prime modulus?

- For the proof of collision resistance
- So $k_j - k_j' ≠ 0$ is guaranteed to be invertible

---
# Binary pedigrees?

Why are pedigree coordinates integers?

- Because the task tree is $n$-ary

But forking tasks is inherently binary...

- Can we make pedigree coordinates binary instead?

---
# Assigning unique task IDs

Root node:

- $\mathrm{root_id} = 0$ &nbsp;&nbsp;&nbsp; (node ID — immutable)
- $\mathrm{root_ix} = 0$ &nbsp;&nbsp;&nbsp; (fork index — mutable)

Task fork (arbitrary precision integers):

- $\mathrm{child_id} = 2^\mathrm{parent_ix} + \mathrm{parent_id}$
- $\mathrm{child_ix} = \mathrm{parent_ix} += 1$

---
# Recovering pedigree

We can easily turn task IDs into binary pedigree vectors:

- Coordinates are binary digits of node ID

How are these coordinates different?

- Coordinates are all zeros and ones
- Not all children of a parent have the same pedigree length
- Easier to view pedigree vectors as having infinite dimensions

---
# Collision proof revisited

With binary coordinates $k_j - k_j'$ is always $±1$
$$\begin{align}
w_j (k_j - k_j') = \delta &\pmod n \\
w_j = (k_j - k_j')\delta = ±\delta &\pmod n
\end{align}$$

- So we can take $n = 2^{64}$ — machine arithmetic
- No more prime modulus shenanigans!

---
# Simplified dot product

This makes incremental dot product computation _very_ simple:

```julia
child_dot = parent_dot + weights[fork_index]
```

That's it:
- Get the random weight for the "fork index"
- Add it to the parent's dot product

---
# Random Weights

DotMix uses a pre-generated array of random weights

- Static — shared between all tasks
- 1024 random UInt64 values (8KiB of static data)
- If the task tree gets deeper than 1024, they recycle weights!

This all seems a bit nuts. Can't we use an RNG to generate weights?

---
# Pseudorandom Weights

We'll use a small auxiliary RNG to generate weights

- 64 bits of aux RNG state
- 64 bit weight value outputs

---
# Pseudorandom Weights

PCG-RXS-M-XS-64 (PCG64) is arguably the best PRNG for this case

```julia
advance(s::UInt64) = 0xd1342543de82ef95*s + 1

function output(s::UInt64)
    s ⊻= s >> ((s >> 59) + 5)
    s *= 0xaef17502108ef2d9
    s ⊻= s >> 43
end
```

- LCG core + strong non-linear bijective output function

---
# DotMix++

Here's (roughly) what's done in Julia 1.10:

```julia
w = aux_rng # use previous state (better ILP)
aux_rng = LCG_MULTIPLIER*aux_rng + 1 # advance LCG

# LCG state => PCG output (weight)
w ⊻= w >> ((w >> 59) + 5)
w *= PCG_MULTIPLIER
w ⊻= w >> 43

main_rng += w # accumulate dot product into main RNG
```

---
# Four Variants

Our main RNG has _four_ 64-bit state registers, not just one...

- We compute four different "independent" weights
- Accumulate a different dot product into each register
- Improves collision resistance from $1/2^{64}$ to $1/2^{256}$

---
# Four Variants

```julia
w = aux_rng
aux_rng = LCG_MULTIPLIER*aux_rng + 1

for register = 1:4
    w += RANDOM_CONSTANT[register]
    w ⊻= w >> ((w >> 59) + 5)
    w *= PCG_MULTIPLIER[register]
    w ⊻= w >> 43

    main_rng[register] += w
end
```

---
# Accumulating into the main RNG

Main RNG registers used to accumulate dot products — is this ok?

- DotMix suggests "seeding" dot products with random initial values
- We're effectively seeding with what main RNG state happens to be

Collision resistance proof can be made to work
- Ehen main RNG use is interleaved with task forking
- Key facts: RNG advance is bijective, $\delta$ doesn't matter
