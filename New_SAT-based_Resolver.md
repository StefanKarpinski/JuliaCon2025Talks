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
- Use an actual SAT solver (PicoSAT)
  - how does optimization work? (you'll see)
- SAT solvers are very sensitive to problem size
  - significant preprocessing to minimize SAT problem size

#### Ends up being fast & scalable

---
# Emergent Features

- Since it doesn't know about version numbers
  - can give it arbitrary preference ordering
- Generates optimal solutions in lexicographical order
  - user can specify priority of packages
- Semi-internal SAT problem API is more generally useful
  - can be used for other related problems

#### Also quite flexible

---
# SAT

A SAT problem consists of:

- A number of variables
- A number of clauses — all must be satisfied
- Each clause is a _disjunction_ of variables and negated variables

Example: $(a \vee ¬b \vee c) \wedge (¬a \vee b)$

- Equivalent: $(b ⇒ (a \vee c)) \wedge (a ⇒ b)$

---
# Encoding Package Problems

Variables:

- One for each package: $p$
  - use $p$ and $q$ for packages
- One for each version: $v$
  - use $v$ and $w$ for versions

---
# Some Notation

Properties:

- Package of a version: $P(v)$
- Versions of a package: $V(p)$
- Dependencies of a version: $D(v)$
- Set of conflicts: $\{v, w\} \in C$

---
# Clauses

| meaning                       | quantifiers             | clause             |
|:-----------------------------:|:-----------------------:|:------------------:|
| version implies its package   | $∀~ v$                  | $v ⇒ P(v)$         |
| package implies some version  | $∀~ p$                  | $p ⇒ \bigvee V(p)$ |
| only one version of a package | $∀~ p, \{v, w\} ⊆ V(p)$ | $¬v \vee ¬w$       |
| versions imply dependencies   | $∀~ v, q \in D(v)$      | $v ⇒ q$            |
| conflicts are exclusive       | $∀~ \{v, w\} \in C$     | $¬v \vee ¬w$       |

---
# Code

Loop over packages

```julia
for p in names
    info_p = info[p]
    n_p = length(info_p.versions) # number of versions of p
    v_p = vars[p]                 # lookup variable for p

    # generate clauses for p
end
```

---
# Code

Version implies its package

```julia
for i = 1:n_p
    PicoSAT.add(pico, -(v_p + i)) # ¬(p@i)
    PicoSAT.add(pico, v_p)        # p
    PicoSAT.add(pico, 0)          # end clause
end
```

---
# Code

Package implies some version

```julia
PicoSAT.add(pico, -v_p)        # ¬p
for i = 1:n_p
    PicoSAT.add(pico, v_p + i) # ¬(p@i)
end
PicoSAT.add(pico, 0)           # end clause
```

---
# Code

Only one version of a package

```julia
exclusive &&
for i = 1:n_p-1, j = i+1:n_p
    PicoSAT.add(pico, -(v_p + i)) # ¬(p@i)
    PicoSAT.add(pico, -(v_p + j)) # ¬(p@j)
    PicoSAT.add(pico, 0)          # end clause
end
```

---
# Code

Versions imply dependencies

```julia
for i = 1:n_p
    for (j, q) in enumerate(info_p.depends)
        info_p.conflicts[i, j] || continue # deps & conflicts
        PicoSAT.add(pico, -(v_p + i)) # ¬(p@i)
        PicoSAT.add(pico, vars[q])    # q
        PicoSAT.add(pico, 0)          # end clause
    end
end
```

---
# Code

Conflicts are exclusive

```julia
for i = 1:n_p
    for q in names
        v_q = vars[q]
        for j = 1:length(info[q].versions)
            info_p.conflicts[i, b+j] || continue
            PicoSAT.add(pico, -(v_p + i)) # ¬(p@i)
            PicoSAT.add(pico, -(v_q + j)) # ¬(p@j)
            PicoSAT.add(pico, 0)          # end clause
        end
    end
end
```
