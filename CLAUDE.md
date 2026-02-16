# CLAUDE.md

## Project

FinanceRoutines.jl — Julia package for financial data (WRDS/CRSP, Compustat, Fama-French, GSW yield curves, bond pricing).

- **Registry**: https://github.com/LouLouLibs/loulouJL (manual updates, no registrator bot)
- **Julia compat**: 1.10+

## Release workflow

1. Bump `version` in `Project.toml`
2. Commit, push, and tag: `git tag vX.Y.Z && git push origin vX.Y.Z`
3. Update the LouLouLibs registry (`F/FinanceRoutines/` in `LouLouLibs/loulouJL`):
   - **Versions.toml**: Add entry with `git-tree-sha1` (get via `git rev-parse vX.Y.Z^{tree}`)
   - **Deps.toml**: Update if deps changed (use version ranges to scope additions/removals)
   - **Compat.toml**: Update if compat bounds changed
   - Can update via GitHub API (`gh api ... -X PUT`) without cloning

## Testing

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

- WRDS tests require `WRDS_USERNAME` and `WRDS_PWD` environment variables
- Local env loaded from `/Users/loulou/Documents/data/.env/.env.gpg` via gpg in `test/runtests.jl`
- Test suites: KenFrench, WRDS, betas, Yields
