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

Julia 1.7-1.9:

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

Julia 1.7-1.9:

```julia
julia> begin
           Random.seed!(0)
           println(repr(rand(UInt64)))
           @async nothing
           println(repr(rand(UInt64)))
       end
0x67dbeba77c5b608f
0x1dc7a124563dedbd # <= different value!
```

---
# The Problem

In Julia 1.7-1.9

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
- If parent has pedigree $\langle k_1, k_2, ..., k_{n-1} \rangle$
- Then $k_n$th child has pedigree $\langle k_1, k_2, ..., k_{n-1}, k_n \rangle$

Every prefix of a task's pedigree is the pedigree of an ancestor

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
\chi\langle k_1, \dots, k_n \rangle = \sum_{i=1}^n w_i k_i \pmod p
$$
- $p$ is a prime modulus
  - necessary for proof of collision resistance
- They use $p = 2^{64} - 59$
  - complicates the implementation a fair bit

---
# DotMix: proof

Suppose two different tasks have the same $\chi$ value:
$$
\sum_{i=1}^n w_i k_i = \sum_{i=1}^n w_i k_i'  \pmod p
$$
Let $j$ be some coordinate where $k_j ≠ k_j'$
$$\begin{align}
w_j (k_j - k_j') &= \delta &&\pmod p \\
w_j &= \delta (k_j - k_j')^{-1} &&\pmod p
\end{align}$$

---
# SplitMix

### So funny story...

Authors spend _a lot of time_ streamlining an implementation of DotMix

- I thought that this optimized version was SplitMix—it's not
- The paper just throws up its hands and does something else

---
# SplitMix

What SplitMix actually is:
```julia
adv(s::UInt64) = s += 0x9E3779B97F4A7C15

function out(s::UInt64)
    s ⊻= s >> 30
    s *= 0xBF58476D1CE4E5B9
    s ⊻= s >> 27
    s *= 0x94D049BB133111EB
    s ⊻= s >> 31
end
```

---
# SplitMix

To generate values in a task:
```julia
state = adv(state)
value = out(state)
```
To spawn a child task:
```julia
parent_state = adv(state)
child_state  = out(state)
```

---
# SplitMix

This is amusing because:

- It's literally what we're doing in Julia 1.7-1.9
- Except we're using a different (better) RNG

If we use this as our main RNG it fixes nothing

- The whole point is for forking tasks _not_ to advance main RNG
- We _could_, however, use SplitMix as an auxiliary RNG (like DotMix)

---
# Too Late

By the time I realized all this, I'd already done something else...
