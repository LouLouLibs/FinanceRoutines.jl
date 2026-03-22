# FinanceRoutines.jl

*Some useful tools to work with academic financial data in Julia*

## Introduction

This package provides a collection of routines for academic finance work.
It gives you a clean pipeline from raw WRDS data (CRSP, Compustat) through to standard research datasets, plus tools for Fama-French factors, treasury yield curves, portfolio construction, and data diagnostics.

File [issues](https://github.com/louloulibs/FinanceRoutines.jl/issues) for comments.


## Installation

`FinanceRoutines.jl` is a registered package in the [`loulouJL`](https://github.com/LouLouLibs/loulouJL) registry.
You can install it via the Julia package manager:

```julia
using Pkg
pkg"registry add https://github.com/LouLouLibs/loulouJL.git"
Pkg.add("FinanceRoutines")
```

Or install directly from GitHub:
```julia
import Pkg
Pkg.add("https://github.com/louloulibs/FinanceRoutines.jl")
```

## Usage

  - WRDS (CRSP, Compustat)
    + [WRDS User Guide](@ref) — download and merge CRSP/Compustat data
    + [Transitioning to the new CRSP file format](@ref) — SIZ to CIZ migration

  - Fama-French factors
    + `import_FF3()` — 3-factor model (market, size, value)
    + `import_FF5()` — 5-factor model (adds profitability, investment)
    + `import_FF_momentum()` — momentum factor
    + All support `:daily`, `:monthly`, `:annual` frequencies

  - Treasury yield curves
    + [Import Yield Curve Data](@ref) — GSW parameters, yields, prices, bond returns

  - Portfolio analytics
    + `calculate_portfolio_returns` — equal/value-weighted returns with optional grouping
    + `calculate_rolling_betas` — rolling window factor regressions
    + `diagnose` — missing rates, duplicates, suspicious values

  - Demos
    + [Estimating Stock Betas](@ref) — unconditional and rolling betas
    + [Advanced WRDS](@ref) — custom Postgres queries

## Other Resources

There are multiple online resources on using the WRDS Postgres database and build the standard finance and accounting datasets:
  
  - Ian D. Gow and Tony Ding: *"Empirical Research in Accounting: Tools and Methods"*; available [here](https://iangow.github.io/far_book/)
  - Chen, Andrew Y. and Tom Zimmermann: *"Open Source Cross-Sectional Asset Pricing"*; 2022, 27:2; available [here](https://www.openassetpricing.com/code/)
  - Christoph Scheuch, Stefan Voigt, Patrick Weiss: *"Tidy Finance with R"*; 2023; Chapman & Hall; available [here](https://www.tidy-finance.org/r/)



## Index

```@index
```