# --------------------------------------------------------------------------------------------------
# PortfolioUtils.jl

# Portfolio-level return calculations
# --------------------------------------------------------------------------------------------------


# --------------------------------------------------------------------------------------------------
"""
    calculate_portfolio_returns(df, ret_col, date_col;
        weighting=:value, weight_col=nothing, groups=nothing)

Calculate portfolio returns from individual stock returns.

# Arguments
- `df::AbstractDataFrame`: Panel data with stock returns
- `ret_col::Symbol`: Column name for returns
- `date_col::Symbol`: Column name for dates

# Keywords
- `weighting::Symbol=:value`: `:equal` for equal-weighted, `:value` for value-weighted
- `weight_col::Union{Nothing,Symbol}=nothing`: Column for weights (required if `weighting=:value`)
- `groups::Union{Nothing,Symbol,Vector{Symbol}}=nothing`: Optional grouping columns (e.g., size quintile)

# Returns
- `DataFrame`: Portfolio returns by date (and group if specified), with column `:port_ret`

# Examples
```julia
# Equal-weighted portfolio returns
df_ew = calculate_portfolio_returns(df, :ret, :datem; weighting=:equal)

# Value-weighted by market cap
df_vw = calculate_portfolio_returns(df, :ret, :datem; weighting=:value, weight_col=:mktcap)

# Value-weighted by group (e.g., size quintile)
df_grouped = calculate_portfolio_returns(df, :ret, :datem;
    weighting=:value, weight_col=:mktcap, groups=:size_quintile)
```
"""
function calculate_portfolio_returns(df::AbstractDataFrame, ret_col::Symbol, date_col::Symbol;
    weighting::Symbol=:value,
    weight_col::Union{Nothing,Symbol}=nothing,
    groups::Union{Nothing,Symbol,Vector{Symbol}}=nothing)

    if weighting == :value && isnothing(weight_col)
        throw(ArgumentError("weight_col required for value-weighted portfolios"))
    end
    if weighting ∉ (:equal, :value)
        throw(ArgumentError("weighting must be :equal or :value, got :$weighting"))
    end

    group_cols = if isnothing(groups)
        [date_col]
    else
        vcat([date_col], groups isa Symbol ? [groups] : groups)
    end

    grouped = groupby(df, group_cols)

    if weighting == :equal
        return combine(grouped, ret_col => (r -> mean(skipmissing(r))) => :port_ret)
    else
        return combine(grouped,
            [ret_col, weight_col] => ((r, w) -> begin
                valid = .!ismissing.(r) .& .!ismissing.(w)
                any(valid) || return missing
                rv, wv = r[valid], w[valid]
                sum(rv .* wv) / sum(wv)
            end) => :port_ret)
    end
end
# --------------------------------------------------------------------------------------------------
