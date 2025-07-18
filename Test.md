---
marp: true
math: mathjax
theme: custom
header: Test Presentation
footer: JuliaCon 2025
---
<!-- _class: lead -->

# Title

## Subtitle

*Stefan Karpinski*

https://JuliaHub.com

---
<!-- _class: default -->

# First slide

Here's some math:
$$
e^{i\pi} = -1
$$

---

# Second slide

```julia
function splitmix64_next(z::UInt64)::UInt64
    z ⊻= z >> 30
    z *= 0xBF58476D1CE4E5B9
    z ⊻= z >> 27
    z *= 0x94D049BB133111EB
    z ⊻= z >> 31
    return z
end
```
