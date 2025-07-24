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

# Resolver.jl

## A New SAT-based Resolver

*Stefan Karpinski*

https://JuliaHub.com

---
<!-- _class: default -->

# Package Version Resolution Problem

The setup:

- There are _packages_
- Each package has _versions_
- Each version _depends_ on a set of packages
- A subset _incompatible_ pairs of versions
  - only makes sense for versions of different packages

---
# Package Version Resolution Problem

A valid solution:

- Every dependency is satisfied
- No incompatible version pairs

A solution satisfies a set of requirements (packages) when:

- The solution contains a version of each required package

---
# Package Version Resolution Problem

The decision problem:

- _Is there a valid solution that satisfies a set of requirements?_

This problem is somewhat famously NP-complete

- If you can solve this you can solve SAT problems
- You might as well use a SAT solver (or something stronger)

Otherwise you'll end up badly implementing a buggy, slow SAT solver

---
# Not Just Any Solution

Obviously just knowing if there is a solution is not that useful

- That's just how computational complexity classes are defined


---
# Optimal Solutions

We also don't just want any solution — we want an optimal solution

- Requires a notion of some solutions

Start by putting a preference ordering on versions of each package

- Extend this to a preference ordering on solutions
- Actually more tricky and subtle than expected

---
# What We Do Now

Pkg.jl includes a version resolver

- Uses belief propagation
- Heuristic: may not find solutions nor necessarily optimal ones
- But, works remarkably well

Implemented and maintained by [Carlo Baldassi](https://github.com/carlobaldassi)

- Thank you, Carlo!

---
# Version Numbers

The biggest issue with the existing resolver:

- Structure & meaning of version numbers deeply baked into logic
- Bakes in that higher version numbers are better
- Can't support pre-release or build numbers

---
# Newer ≠ Better? 

When would you prefer older versions over newer ones?

- Version fixing — prefer current version
  - minimize changes to manifests
- Download avoidance — prefer pre-installed versions
  - avoid installing new versions if possible
- Downgrade resolution prefer oldest allowable versions
  - useful for testing lower compat bounds

We do all of these in hacky ways currently

---
# Resolver.jl Approach

- Avoid coupling with details of packages, versions, registries
  - Resolver.jl doesn't know about any of these
- Use an actual SAT solver (`libpicosat`)
  - but how does optimization work?
- SAT solvers are very sensitive to problem size
  - significant preprocessing to minimize SAT problem size
- Semi-internal SAT problem API is more broadly useful
