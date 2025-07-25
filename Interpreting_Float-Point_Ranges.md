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

Example: `-1e25:3e20:2e25`

```julia
julia> r = -1e25:3e20:2e25
-1.0e25:3.0e20:1.9999999999999998e25

julia> r[33334]
-1.0000000000048549e20

julia> r[33335]
1.999999999988235e20
```

---
# Another example

Example: `-1e25:3e20:2e25`

- `1e25` means $10000000000000000905969664 ± 2147483648$
- `3e20` means $300000000000000000000 ± 65536$
- `2e25` means $20000000000000001811939328 ± 4294967296$

Need to pick the "correct" value in each interval

- In this case, obviously meant to be $m × 10^p$ for small $m$
