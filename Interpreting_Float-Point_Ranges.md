---
marp: true
math: mathjax
theme: custom
header: Resolver.jl
paginate: true
---
<!-- _class: lead -->
<!-- _footer: JuliaCon 2025 -->
<!-- _paginate: false -->

# Floating-point Ranges

## Why are they so hard?

### Can we do better?

*Stefan Karpinski*

https://JuliaHub.com

---
<!-- _class: default -->

# Why are float ranges hard?

Consider `0.1:0.2:1.7`

- Let's try generating the values naively

---
# Naive generation?

```julia
julia> [0.1 + i*0.2 for i=0:8]
9-element Vector{Float64}:
 0.1
 0.30000000000000004
 0.5
 0.7000000000000001
 0.9
 1.1
 1.3000000000000003
 1.5000000000000002
 1.7000000000000002
```

---
# Why this is happening

The source of 99% of confusion about floating-point:

- `0.1` actually means $\frac{3602879701896397}{2^{55}} > \frac{1}{10}$
- `0.2` actually means $\frac{3602879701896397}{2^{54}} > \frac{2}{10}$
- `1.7` actually means $\frac{7656119366529843}{2^{52}} < \frac{17}{10}$

Taken literally, we cannot have `start + n*step == stop`

---
# Face value?

When evaluating `sin(0.1)` we compute
$$
\sin \frac{3602879701896397}{2^{55}}
$$
- And round back to `Float64`

We don't compute $\sin \frac{1}{10}$

---
# Interpretation required

Sadly, we need to do some amount of guessing here

- Actual start, step and stop values are usually incoherent

Each value has some wiggle room if interpreted as an interval

- Interpret `x` as the set of values in $\mathbb{R}$ that round to `x`

---
# Another example

```julia
julia> r = -3e25:1e25:4e25
-3.0e25:1.0e25:3.000000000000001e25

julia> collect(r)
7-element Vector{Float64}:
 -3.0e25
 -1.9999999999999998e25
 -9.999999999999999e24
  4.294967296e9         # <= should be zero
  1.0000000000000003e25
  2.0e25
  3.000000000000001e25
```

---
# Another example

Range: `-3e25:1e25:4e25`

- `3e25` $= 30000000000000000570425344 ±2^{32}$
- `1e25` $= 10000000000000000905969664 ±2^{31}$
- `4e25` $= 40000000000000003623878656 ±2^{33}$

---
# What we do now

Guessing what `a:s:b` means (today):

- Compute length `n = round((b-a)/s)`
- Rationalize `a` to `n_a//d_a`
- Rationalize `b` to `n_b//d_b`
- Compute `n_s//d_s = (n_b//d_b - n_a//d_a)/n`
- Check if `float(n_s//d_s) == s`

Otherwise fall back to literal (bad) interpretation

---
# Let's formalize things

We'll view float inputs as intervals:

- `a:s:b` $\rightarrow (A, S, B) \subseteq \mathbb{R}^3$
  - where $A   = [A^-, A^+] \subseteq \mathbb{R}$
  - where $S\, = [S^-, S^+] \subseteq \mathbb{R}$
  - where $B   = [B^-, B^+] \subseteq \mathbb{R}$

---
# Definitions

An _rational interpretation_ of a range:
$$(\alpha, \beta, \sigma) \in (A × B × S) \cap \mathbb{Q}^3$$
$$\alpha + n\sigma = \beta ~~\text{for some}~~ n \in \mathbb{Z}$$

Refer to $n$ as the length

- even though ranges iterates $n+1$ values
- nicer value: `length(-1e6:1e6) == 2e6 + 1`

---
# Picking interpretations

There are infinite interpretations for any feasible range

- How do we pick a good interpretation?
- This is the whole problem

Needs to be practical to compute
