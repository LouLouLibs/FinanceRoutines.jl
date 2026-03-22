# --------------------------------------------------------------------------------------------------
# EventStudy.jl

# Event study utilities for computing abnormal returns around events
# --------------------------------------------------------------------------------------------------


# --------------------------------------------------------------------------------------------------
"""
    event_study(events, returns;
        event_window=(-10, 10), estimation_window=(-260, -11),
        model=:market_adjusted,
        id_col=:permno, date_col=:date, ret_col=:ret,
        event_date_col=:event_date, market_col=:mktrf)

Compute cumulative abnormal returns (CAR) and buy-and-hold abnormal returns (BHAR)
around events using standard event study methodology.

# Arguments
- `events::AbstractDataFrame`: One row per event with entity ID and event date
- `returns::AbstractDataFrame`: Panel of returns with entity ID, date, and return

# Keywords
- `event_window::Tuple{Int,Int}=(-10, 10)`: Trading days around event (inclusive)
- `estimation_window::Tuple{Int,Int}=(-260, -11)`: Trading days for estimating normal returns
- `model::Symbol=:market_adjusted`: Normal return model:
  - `:market_adjusted` — abnormal = ret - mktrf
  - `:market_model` — OLS α+β on market in estimation window
  - `:mean_adjusted` — abnormal = ret - mean(ret in estimation window)
- `id_col::Symbol=:permno`: Entity identifier column (must exist in both DataFrames)
- `date_col::Symbol=:date`: Date column in returns
- `ret_col::Symbol=:ret`: Return column in returns
- `event_date_col::Symbol=:event_date`: Event date column in events
- `market_col::Symbol=:mktrf`: Market return column in returns (for `:market_adjusted` and `:market_model`)

# Returns
- `DataFrame` with columns:
  - All columns from `events`
  - `:car` — Cumulative Abnormal Return over the event window
  - `:bhar` — Buy-and-Hold Abnormal Return over the event window
  - `:n_obs` — Number of non-missing return observations in the event window

# Examples
```julia
events = DataFrame(permno=[10001, 10002], event_date=[Date("2010-06-15"), Date("2011-03-20")])

# Market-adjusted (simplest)
results = event_study(events, df_msf)

# Market model with custom windows
results = event_study(events, df_msf;
    event_window=(-5, 5), estimation_window=(-252, -21),
    model=:market_model)

# Mean-adjusted (no market return needed)
results = event_study(events, df_msf; model=:mean_adjusted)
```

# Notes
- **Experimental:** this function has not been extensively validated against established
  event study implementations. Verify results independently before relying on them.
- Returns must be sorted by (id, date) and contain trading days only
- Events with insufficient estimation window data are included with `missing` CAR/BHAR
- The function uses relative trading-day indexing (not calendar days)
"""
function event_study(events::AbstractDataFrame, returns::AbstractDataFrame;
    event_window::Tuple{Int,Int}=(-10, 10),
    estimation_window::Tuple{Int,Int}=(-260, -11),
    model::Symbol=:market_adjusted,
    id_col::Symbol=:permno,
    date_col::Symbol=:date,
    ret_col::Symbol=:ret,
    event_date_col::Symbol=:event_date,
    market_col::Symbol=:mktrf)

    if model ∉ (:market_adjusted, :market_model, :mean_adjusted)
        throw(ArgumentError("model must be :market_adjusted, :market_model, or :mean_adjusted, got :$model"))
    end
    if event_window[1] > event_window[2]
        throw(ArgumentError("event_window start must be ≤ end"))
    end
    if estimation_window[1] > estimation_window[2]
        throw(ArgumentError("estimation_window start must be ≤ end"))
    end
    if model != :mean_adjusted && market_col ∉ propertynames(returns)
        throw(ArgumentError("returns must contain market column :$market_col for model :$model"))
    end

    # Sort returns by entity and date
    returns_sorted = sort(returns, [id_col, date_col])

    # Group returns by entity for fast lookup
    returns_by_id = groupby(returns_sorted, id_col)

    # Process each event
    car_vec = Union{Missing, Float64}[]
    bhar_vec = Union{Missing, Float64}[]
    nobs_vec = Union{Missing, Int}[]

    for row in eachrow(events)
        entity_id = row[id_col]
        event_date = row[event_date_col]

        # Find this entity's returns
        key = (entity_id,)
        if !haskey(returns_by_id, key)
            push!(car_vec, missing)
            push!(bhar_vec, missing)
            push!(nobs_vec, 0)
            continue
        end

        entity_rets = returns_by_id[key]
        dates = entity_rets[!, date_col]

        # Find the event date index in the trading calendar
        event_idx = findfirst(d -> d >= event_date, dates)
        if isnothing(event_idx)
            push!(car_vec, missing)
            push!(bhar_vec, missing)
            push!(nobs_vec, 0)
            continue
        end

        # Extract event window and estimation window by trading-day offset
        ew_start = event_idx + event_window[1]
        ew_end = event_idx + event_window[2]
        est_start = event_idx + estimation_window[1]
        est_end = event_idx + estimation_window[2]

        # Bounds check
        if ew_start < 1 || ew_end > nrow(entity_rets) || est_start < 1 || est_end > nrow(entity_rets)
            push!(car_vec, missing)
            push!(bhar_vec, missing)
            push!(nobs_vec, 0)
            continue
        end

        # Get event window returns
        ew_rets = entity_rets[ew_start:ew_end, ret_col]

        # Compute abnormal returns based on model
        abnormal_rets = _compute_abnormal_returns(
            model, entity_rets, ew_rets,
            ew_start, ew_end, est_start, est_end,
            ret_col, market_col)

        if ismissing(abnormal_rets)
            push!(car_vec, missing)
            push!(bhar_vec, missing)
            push!(nobs_vec, 0)
            continue
        end

        valid = .!ismissing.(abnormal_rets)
        n_valid = count(valid)

        if n_valid == 0
            push!(car_vec, missing)
            push!(bhar_vec, missing)
            push!(nobs_vec, 0)
        else
            ar = collect(skipmissing(abnormal_rets))
            push!(car_vec, sum(ar))
            push!(bhar_vec, prod(1.0 .+ ar) - 1.0)
            push!(nobs_vec, n_valid)
        end
    end

    result = copy(events)
    result[!, :car] = car_vec
    result[!, :bhar] = bhar_vec
    result[!, :n_obs] = nobs_vec

    return result
end
# --------------------------------------------------------------------------------------------------


# --------------------------------------------------------------------------------------------------
function _compute_abnormal_returns(model::Symbol, entity_rets, ew_rets,
    ew_start, ew_end, est_start, est_end,
    ret_col, market_col)

    if model == :market_adjusted
        ew_mkt = entity_rets[ew_start:ew_end, market_col]
        return _safe_subtract(ew_rets, ew_mkt)

    elseif model == :mean_adjusted
        est_rets = entity_rets[est_start:est_end, ret_col]
        valid_est = collect(skipmissing(est_rets))
        length(valid_est) < 10 && return missing
        mu = mean(valid_est)
        return [ismissing(r) ? missing : r - mu for r in ew_rets]

    elseif model == :market_model
        est_rets = entity_rets[est_start:est_end, ret_col]
        est_mkt = entity_rets[est_start:est_end, market_col]

        # Need non-missing pairs for OLS
        valid = .!ismissing.(est_rets) .& .!ismissing.(est_mkt)
        count(valid) < 30 && return missing

        y = Float64.(est_rets[valid])
        x = Float64.(est_mkt[valid])

        # OLS: y = α + β*x
        n = length(y)
        x_mean = mean(x)
        y_mean = mean(y)
        β = sum((x .- x_mean) .* (y .- y_mean)) / sum((x .- x_mean) .^ 2)
        α = y_mean - β * x_mean

        # Abnormal returns in event window
        ew_mkt = entity_rets[ew_start:ew_end, market_col]
        return [ismissing(r) || ismissing(m) ? missing : r - (α + β * m)
                for (r, m) in zip(ew_rets, ew_mkt)]
    end
end

function _safe_subtract(a, b)
    return [ismissing(x) || ismissing(y) ? missing : x - y for (x, y) in zip(a, b)]
end
# --------------------------------------------------------------------------------------------------
