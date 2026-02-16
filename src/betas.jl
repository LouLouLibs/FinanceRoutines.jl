# --------------------------------------------------------------------------------------------------
# betas.jl

# estimating regressions on financial data ...


# List of exported functions
# --------------------------------------------------------------------------------------------------


# --------------------------------------------------------------------------------------------------
"""
    calculate_rolling_betas(y, x; window=60)

Calculate rolling betas using `window` months of returns.
"""
function calculate_rolling_betas(X, y; 
    window=60, min_data=nothing,
    method = :linalg)

    n, p = size(X)
    _min_data = something(min_data, p)

    res = Array{Union{Missing, Float64}}(missing, (n,p))

    if method == :linalg
        for i in window:n
            X_window = @view X[i-window+1:i, :]
            y_window = @view y[i-window+1:i]

            non_missing = .!any(ismissing.(X_window), dims=2)[:] .& .!ismissing.(y_window)
            (sum(non_missing) < _min_data) && continue

            X_non_missing = @view X_window[non_missing, :]
            y_non_missing = @view y_window[non_missing]

            res[i, :] = qr(X_non_missing) \ y_non_missing
        end
    elseif method == :lm
        for i in window:n
            X_window = @view X[i-window+1:i, :]
            y_window = @view y[i-window+1:i]

            non_missing = .!any(ismissing.(X_window), dims=2)[:] .& .!ismissing.(y_window)
            (sum(non_missing) < _min_data) && continue

            X_non_missing = @view X_window[non_missing, :]
            y_non_missing = @view y_window[non_missing]

            res[i, :] = coef(lm(disallowmissing(X_non_missing), disallowmissing(y_non_missing)))
        end
    else
       throw(ArgumentError("method must be one of: :linalg, :lm"))
    end    

    return res
end
# --------------------------------------------------------------------------------------------------


# --------------------------------------------------------------------------------------------------
