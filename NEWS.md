# FinanceRoutines.jl Changelog

## v0.5.0

### Breaking changes
- `ImportYields.jl` split into `GSW.jl` (yield curve model) and `BondPricing.jl` (bond math). No public API changes, but code that `include`d `ImportYields.jl` directly will need updating.
- Missing-value flags expanded: `-999.0`, `-9999.0`, `-99.99` now treated as missing in GSW data (previously only `-999.99`). **Migration note:** if your downstream code relied on these numeric values (e.g., `-999.0` as an actual number), they will now silently become `missing`. Check any filtering or aggregation that might be affected.

### New features
- `import_FF5`: Import Fama-French 5-factor model data (market, size, value, profitability, investment)
- `import_FF_momentum`: Import Fama-French momentum factor
- `calculate_portfolio_returns`: Value-weighted and equal-weighted portfolio return calculations
- `diagnose`: Data quality diagnostics for financial DataFrames
- WRDS connection now warns about Duo 2FA and gives clear guidance on failure

### Internal improvements
- Removed broken `@log_msg` macro, replaced with `@debug`
- Removed stale `export greet_FinanceRoutines` (function was never defined)
- Removed `Logging` from dependencies (macros available from Base)
- Ken French file parsing generalized with shared helpers for FF3/FF5 reuse
- CI now filters by path (skips runs for docs-only changes)
