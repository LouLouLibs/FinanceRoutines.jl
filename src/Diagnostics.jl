# --------------------------------------------------------------------------------------------------
# Diagnostics.jl

# Data quality diagnostics for financial DataFrames
# --------------------------------------------------------------------------------------------------


# --------------------------------------------------------------------------------------------------
"""
    diagnose(df; id_col=:permno, date_col=:date, ret_col=:ret, price_col=:prc)

Run data quality diagnostics on a financial DataFrame.

# Arguments
- `df::AbstractDataFrame`: The data to diagnose

# Keywords
- `id_col::Symbol=:permno`: Entity identifier column
- `date_col::Symbol=:date`: Date column
- `ret_col::Union{Nothing,Symbol}=:ret`: Return column (set to `nothing` to skip)
- `price_col::Union{Nothing,Symbol}=:prc`: Price column (set to `nothing` to skip)

# Returns
- `Dict{Symbol, Any}` with keys:
  - `:nrow`, `:ncol` — dimensions
  - `:missing_rates` — `Dict{Symbol, Float64}` fraction missing per column
  - `:duplicate_keys` — count of duplicate (id, date) pairs (if both columns exist)
  - `:suspicious_values` — `Vector{String}` descriptions of anomalies found

# Examples
```julia
df = import_MSF(conn; date_range=(Date("2020-01-01"), Date("2022-12-31")))
report = diagnose(df)
report[:missing_rates]      # Dict(:permno => 0.0, :ret => 0.02, ...)
report[:duplicate_keys]     # 0
report[:suspicious_values]  # ["15 returns outside [-100%, +100%]"]
```
"""
function diagnose(df::AbstractDataFrame;
    id_col::Symbol=:permno, date_col::Symbol=:date,
    ret_col::Union{Nothing,Symbol}=:ret,
    price_col::Union{Nothing,Symbol}=:prc)

    report = Dict{Symbol, Any}()
    report[:nrow] = nrow(df)
    report[:ncol] = ncol(df)

    # Missing rates
    missing_rates = Dict{Symbol, Float64}()
    for col in names(df)
        col_sym = Symbol(col)
        missing_rates[col_sym] = nrow(df) > 0 ? count(ismissing, df[!, col]) / nrow(df) : 0.0
    end
    report[:missing_rates] = missing_rates

    # Duplicate keys
    if id_col in propertynames(df) && date_col in propertynames(df)
        report[:duplicate_keys] = nrow(df) - nrow(unique(df, [id_col, date_col]))
    end

    # Suspicious values
    suspicious = String[]
    if !isnothing(ret_col) && ret_col in propertynames(df)
        n_extreme = count(r -> !ismissing(r) && (r > 1.0 || r < -1.0), df[!, ret_col])
        n_extreme > 0 && push!(suspicious, "$n_extreme returns outside [-100%, +100%]")
    end
    if !isnothing(price_col) && price_col in propertynames(df)
        n_neg = count(r -> !ismissing(r) && r < 0, df[!, price_col])
        n_neg > 0 && push!(suspicious, "$n_neg negative prices (CRSP convention for bid/ask midpoint)")
    end
    report[:suspicious_values] = suspicious

    return report
end
# --------------------------------------------------------------------------------------------------
