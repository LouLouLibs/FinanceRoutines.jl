# --------------------------------------------------------------------------------------------------
# ImportYields.jl

# Collection of functions that import Treasury Yields data
# --------------------------------------------------------------------------------------------------


# --------------------------------------------------------------------------------------------------
# GSW Parameter Type Definition
# --------------------------------------------------------------------------------------------------

"""
    GSWParameters

Structure to hold Gürkaynak-Sack-Wright Nelson-Siegel-Svensson model parameters.

# Fields
- `β₀::Float64`: Level parameter (BETA0)
- `β₁::Float64`: Slope parameter (BETA1) 
- `β₂::Float64`: Curvature parameter (BETA2)
- `β₃::Float64`: Second curvature parameter (BETA3) - may be missing if model uses 3-factor version
- `τ₁::Float64`: First decay parameter (TAU1, must be positive)
- `τ₂::Float64`: Second decay parameter (TAU2, must be positive) - may be missing if model uses 3-factor version

# Examples
```julia
# Create GSW parameters manually (4-factor model)
params = GSWParameters(5.0, -2.0, 1.5, 0.8, 2.5, 0.5)

# Create GSW parameters for 3-factor model (when τ₂/β₃ are missing)
params_3factor = GSWParameters(5.0, -2.0, 1.5, missing, 2.5, missing)

# Create from DataFrame row
df = import_gsw_parameters()
params = GSWParameters(df[1, :])  # First row

# Access individual parameters
println("Level: ", params.β₀)
println("Slope: ", params.β₁)
```

# Notes
- Constructor validates that available decay parameters are positive
- Handles missing values for τ₂ and β₃ (common when using 3-factor Nelson-Siegel model)
- When τ₂ or β₃ are missing, the model degenerates to the 3-factor Nelson-Siegel form
- Can be constructed from DataFrameRow for convenience
"""
struct GSWParameters
    β₀::Union{Float64, Missing}  # Level
    β₁::Union{Float64, Missing}  # Slope  
    β₂::Union{Float64, Missing}  # Curvature 1
    β₃::Union{Float64, Missing}  # Curvature 2 (may be missing for 3-factor model)
    τ₁::Union{Float64, Missing}  # Decay 1 (must be positive when present)
    τ₂::Union{Float64, Missing}  # Decay 2 (may be missing for 3-factor model)
    
    # Inner constructor with validation
    function GSWParameters(β₀, β₁, β₂, β₃, τ₁, τ₂)

        # Check if core parameters are missing
        if ismissing(β₀) || ismissing(β₁) || ismissing(β₂) || ismissing(τ₁)
            return missing
        end

        # Validate that non-missing decay parameters are positive
        if !ismissing(τ₁) && τ₁ <= 0
            throw(ArgumentError("First decay parameter τ₁ must be positive when present, got τ₁=$τ₁"))
        end
        if !ismissing(τ₂) && τ₂ <= 0
            throw(ArgumentError("Second decay parameter τ₂ must be positive when present, got τ₂=$τ₂"))
        end
        
        # Convert to appropriate types
        new(
            ismissing(β₀) ? missing : Float64(β₀),
            ismissing(β₁) ? missing : Float64(β₁), 
            ismissing(β₂) ? missing : Float64(β₂),
            ismissing(β₃) ? missing : Float64(β₃),
            ismissing(τ₁) ? missing : Float64(τ₁), 
            ismissing(τ₂) ? missing : Float64(τ₂)
        )
    end
end

# Convenience constructors
"""
    GSWParameters(row::DataFrameRow)

Create GSWParameters from a DataFrame row containing BETA0, BETA1, BETA2, BETA3, TAU1, TAU2 columns.
Handles missing values (including -999 flags) gracefully.
"""
function GSWParameters(row::DataFrameRow)
    return GSWParameters(row.BETA0, row.BETA1, row.BETA2, row.BETA3, row.TAU1, row.TAU2)
end

"""
    GSWParameters(row::NamedTuple)

Create GSWParameters from a NamedTuple containing the required fields.
Handles missing values (including -999 flags) gracefully.
"""
function GSWParameters(row::NamedTuple)
    return GSWParameters(row.BETA0, row.BETA1, row.BETA2, row.BETA3, row.TAU1, row.TAU2)
end


"""
    is_three_factor_model(params::GSWParameters)

Check if GSW parameters represent a 3-factor Nelson-Siegel model (missing β₃ and τ₂).

# Returns
- `Bool`: true if this is a 3-factor model, false if 4-factor Svensson model
"""
function is_three_factor_model(params::GSWParameters)
    return ismissing(params.β₃) || ismissing(params.τ₂)
end

# Helper function to extract parameters as tuple, handling missing values
"""
    _extract_params(params::GSWParameters)

Extract parameters as tuple for use in calculation functions.
For 3-factor models, uses τ₁ for both decay parameters and sets β₃=0.
"""
function _extract_params(params::GSWParameters)
    # Handle 3-factor vs 4-factor models
    if is_three_factor_model(params)
        # For 3-factor model: set β₃=0 and use τ₁ for both decay parameters
        β₃ = 0.0
        τ₂ = ismissing(params.τ₂) ? params.τ₁ : params.τ₂
    else
        β₃ = params.β₃
        τ₂ = params.τ₂
    end
    
    return (params.β₀, params.β₁, params.β₂, β₃, params.τ₁, τ₂)
end
# --------------------------------------------------------------------------------------------------



# --------------------------------------------------------------------------------------------------
"""
    import_gsw_parameters(; date_range=nothing, validate=true)

Import Gürkaynak-Sack-Wright (GSW) yield curve parameters from the Federal Reserve.

Downloads the daily GSW yield curve parameter estimates from the Fed's website and returns
a cleaned DataFrame with the Nelson-Siegel-Svensson model parameters.

# Arguments
- `date_range::Union{Nothing, Tuple{Date, Date}}`: Optional date range for filtering data. 
  If `nothing`, returns all available data. Default: `nothing`
- `validate::Bool`: Whether to validate input parameters and data quality. Default: `true`

# Returns
- `DataFrame`: Contains columns `:date`, `:BETA0`, `:BETA1`, `:BETA2`, `:BETA3`, `:TAU1`, `:TAU2`

# Throws
- `ArgumentError`: If date range is invalid
- `HTTP.ExceptionRequest.StatusError`: If download fails
- `Exception`: If data parsing fails

# Examples
```julia
# Import all available data
df = import_gsw_parameters()

# Import data for specific date range  
df = import_gsw_parameters(date_range=(Date("2020-01-01"), Date("2023-12-31")))

# Import without validation (faster, but less safe)
df = import_gsw_parameters(validate=false)
```

# Notes
- Data source: Federal Reserve Economic Data (FRED)
- The GSW model uses the Nelson-Siegel-Svensson functional form
- Missing values in the original data are converted to `missing`
- Data is automatically sorted by date
- Additional variables: 
  - Zero-coupon yield,Continuously Compounded,SVENYXX
  - Par yield,Coupon-Equivalent,SVENPYXX
  - Instantaneous forward rate,Continuously Compounded,SVENFXX
  - One-year forward rate,Coupon-Equivalent,SVEN1FXX

"""
function import_gsw_parameters(; 
    date_range::Union{Nothing, Tuple{Date, Date}} = nothing,
    additional_variables::Vector{Symbol}=Symbol[],
    validate::Bool = true)
    
    
    # Download data with error handling
    @info "Downloading GSW Yield Curve Parameters from Federal Reserve"
    
    try
        url_gsw = "https://www.federalreserve.gov/data/yield-curve-tables/feds200628.csv"
        temp_file = Downloads.download(url_gsw)
        
        # Parse CSV with proper error handling
        df_gsw = CSV.read(temp_file, DataFrame, 
                         skipto=11, 
                         header=10,
                         silencewarnings=true)
        
        # Clean up temporary file
        rm(temp_file, force=true)
        
        # Clean and process the data
        df_clean = _clean_gsw_data(df_gsw, date_range; additional_variables=additional_variables) 

        
        if validate
            _validate_gsw_data(df_clean)
        end
        
        @info "Successfully imported $(nrow(df_clean)) rows of GSW parameters"
        return df_clean
        
    catch e
        if e isa Downloads.RequestError
            throw(ArgumentError("Failed to download GSW data from Federal Reserve. Check internet connection."))
        elseif e isa CSV.Error  
            throw(ArgumentError("Failed to parse GSW data. The file format may have changed."))
        else
            rethrow(e)
        end
    end
end



"""
    _clean_gsw_data(df_raw, date_range)

Clean and format the raw GSW data from the Federal Reserve.
"""
function _clean_gsw_data(df_raw::DataFrame,
    date_range::Union{Nothing, Tuple{Date, Date}};
    additional_variables::Vector{Symbol}=Symbol[])


    # Make a copy to avoid modifying original
    df = copy(df_raw)    
    # Standardize column names
    rename!(df, "Date" => "date")
    
    # Apply date filtering if specified
    if !isnothing(date_range)
        start_date, end_date = date_range
        if start_date > end_date
            @warn "starting date posterior to end date ... shuffling them around"
            start_date, end_date = min(start_date, end_date), max(start_date, end_date)
        end
        filter!(row -> start_date <= row.date <= end_date, df)
    end
    
    # Select and order relevant columns
    parameter_cols = vcat(
        [:BETA0, :BETA1, :BETA2, :BETA3, :TAU1, :TAU2],
        intersect(additional_variables, propertynames(df))        
        ) |> unique
    select!(df, :date, parameter_cols...)
    
    # Convert parameter columns to Float64, handling missing values
    for col in parameter_cols
        transform!(df, col => ByRow(_safe_parse_float) => col)
    end
    
    # Sort by date for consistency
    sort!(df, :date)
    
    return df
end

"""
    _safe_parse_float(value)

Safely parse a value to Float64, returning missing for unparseable values.
Handles common flag values for missing data in economic datasets.
"""
function _safe_parse_float(value)
    if ismissing(value) || value == ""
        return missing
    end
    
    # Handle string values
    if value isa AbstractString
        parsed = tryparse(Float64, strip(value))
        if isnothing(parsed)
            return missing
        end
        value = parsed
    end
    
    # Handle numeric values and check for common missing data flags
    try
        numeric_value = Float64(value)
        
        # Check for common missing data flags used in economic datasets
        # -999, -9999 are common flags for missing/unavailable data
        if numeric_value == -999.99 
            return missing
        end
        
        return numeric_value
    catch
        return missing
    end
end

"""
    _validate_gsw_data(df)

Validate the cleaned GSW data for basic quality checks.
"""
function _validate_gsw_data(df::DataFrame)
    if nrow(df) == 0
        throw(ArgumentError("No data found for the specified date range"))
    end
    
    # Check for required columns
    required_cols = [:date, :BETA0, :BETA1, :BETA2, :BETA3, :TAU1, :TAU2]
    missing_cols = setdiff(required_cols, propertynames(df))
    if !isempty(missing_cols)
        throw(ArgumentError("Missing required columns: $(missing_cols)"))
    end
    
    # Check for reasonable parameter ranges (basic sanity check)
    param_cols = [:BETA0, :BETA1, :BETA2, :BETA3, :TAU1, :TAU2]
    for col in param_cols
        col_data = skipmissing(df[!, col]) |> collect
        if length(col_data) == 0
            @warn "Column $col contains only missing values"
        end
    end
    
    # Check date continuity (warn if there are large gaps)
    if nrow(df) > 1
        date_diffs = diff(df.date)
        large_gaps = findall(x -> x > Day(7), date_diffs)
        if !isempty(large_gaps)
            @warn "Found $(length(large_gaps)) gaps larger than 7 days in the data"
        end
    end
end
# --------------------------------------------------------------------------------------------------



# --------------------------------------------------------------------------------------------------
# GSW Core Calculation Functions

# Method 1: Using GSWParameters struct (preferred for clean API)
"""
    gsw_yield(maturity, params::GSWParameters)

Calculate yield from GSW Nelson-Siegel-Svensson parameters using parameter struct.

# Arguments
- `maturity::Real`: Time to maturity in years (must be positive)
- `params::GSWParameters`: GSW parameter struct

# Returns
- `Float64`: Yield in percent (e.g., 5.0 for 5%)

# Examples
```julia
params = GSWParameters(5.0, -2.0, 1.5, 0.8, 2.5, 0.5)
yield = gsw_yield(10.0, params)
```
"""
function gsw_yield(maturity::Real, params::GSWParameters)
    return gsw_yield(maturity, _extract_params(params)...)
end

# Method 2: Using individual parameters (for flexibility and backward compatibility)
"""
    gsw_yield(maturity, β₀, β₁, β₂, β₃, τ₁, τ₂)

Calculate yield from Gürkaynak-Sack-Wright Nelson-Siegel-Svensson parameters.

Computes the yield for a given maturity using the Nelson-Siegel-Svensson functional form
with the GSW parameter estimates. Automatically handles 3-factor vs 4-factor models.

# Arguments
- `maturity::Real`: Time to maturity in years (must be positive)
- `β₀::Real`: Level parameter (BETA0)
- `β₁::Real`: Slope parameter (BETA1) 
- `β₂::Real`: Curvature parameter (BETA2)
- `β₃::Real`: Second curvature parameter (BETA3) - set to 0 or missing for 3-factor model
- `τ₁::Real`: First decay parameter 
- `τ₂::Real`: Second decay parameter - can equal τ₁ for 3-factor model

# Returns
- `Float64`: Yield in percent (e.g., 5.0 for 5%)

# Throws
- `ArgumentError`: If maturity is non-positive or τ parameters are non-positive

# Examples
```julia
# Calculate 1-year yield (4-factor model)
yield = gsw_yield(1.0, 5.0, -2.0, 1.5, 0.8, 2.5, 0.5)

# Calculate 10-year yield (3-factor model, β₃=0)
yield = gsw_yield(10.0, 5.0, -2.0, 1.5, 0.0, 2.5, 2.5)
```

# Notes
- Based on the Nelson-Siegel-Svensson functional form
- When β₃=0 or τ₂=τ₁, degenerates to 3-factor Nelson-Siegel model
- Returns yield in percentage terms (not decimal)
- Function is vectorizable: use `gsw_yield.(maturities, β₀, β₁, β₂, β₃, τ₁, τ₂)`
"""
function gsw_yield(maturity::Real, 
    β₀::Real, β₁::Real, β₂::Real, β₃::Real, τ₁::Real, τ₂::Real)
    
    # Input validation
    if maturity <= 0
        throw(ArgumentError("Maturity must be positive, got $maturity"))
    end
    
    # Handle any missing values
    if any(ismissing, [β₀, β₁, β₂, β₃, τ₁, τ₂])
        return missing
    end
    
    # For 3-factor model compatibility: if β₃ is 0 or very small, skip the fourth term
    use_four_factor = !ismissing(β₃) && abs(β₃) > 1e-10 && !ismissing(τ₂) && τ₂ > 0
    
    # Nelson-Siegel-Svensson formula
    t = Float64(maturity)
    
    # Calculate decay terms
    exp_t_τ₁ = exp(-t/τ₁)
    
    # yield terms
    term1 = β₀                                           # Level
    term2 = β₁ * (1.0 - exp_t_τ₁) / (t/τ₁)               # Slope  
    term3 = β₂ * ((1.0 - exp_t_τ₁) / (t/τ₁) - exp_t_τ₁)  # First curvature
    
    # Fourth term only for 4-factor Svensson model
    term4 = if use_four_factor
        exp_t_τ₂ = exp(-t/τ₂)
        β₃ * ((1.0 - exp_t_τ₂) / (t/τ₂) - exp_t_τ₂)  # Second curvature
    else
        0.0
    end

    yield = term1 + term2 + term3 + term4

    return Float64(yield)
end

# Method 1: Using GSWParameters struct
"""
    gsw_price(maturity, params::GSWParameters; face_value=1.0)

Calculate zero-coupon bond price from GSW parameters using parameter struct.

# Arguments
- `maturity::Real`: Time to maturity in years (must be positive)
- `params::GSWParameters`: GSW parameter struct
- `face_value::Real`: Face value of the bond (default: 1.0)

# Returns
- `Float64`: Bond price

# Examples
```julia
params = GSWParameters(5.0, -2.0, 1.5, 0.8, 2.5, 0.5)
price = gsw_price(10.0, params)
```
"""
function gsw_price(maturity::Real, params::GSWParameters; face_value::Real = 1.0)
    return gsw_price(maturity, _extract_params(params)..., face_value=face_value)
end

# Method 2: Using individual parameters
"""
    gsw_price(maturity, β₀, β₁, β₂, β₃, τ₁, τ₂; face_value=1.0)

Calculate zero-coupon bond price from GSW Nelson-Siegel-Svensson parameters.

Computes the price of a zero-coupon bond using the yield derived from GSW parameters.

# Arguments
- `maturity::Real`: Time to maturity in years (must be positive)
- `β₀::Real`: Level parameter (BETA0)
- `β₁::Real`: Slope parameter (BETA1)
- `β₂::Real`: Curvature parameter (BETA2) 
- `β₃::Real`: Second curvature parameter (BETA3)
- `τ₁::Real`: First decay parameter 
- `τ₂::Real`: Second decay parameter
- `face_value::Real`: Face value of the bond (default: 1.0)

# Returns
- `Float64`: Bond price

# Throws
- `ArgumentError`: If maturity is non-positive, τ parameters are non-positive, or face_value is non-positive

# Examples
```julia
# Calculate price of 1-year zero-coupon bond
price = gsw_price(1.0, 5.0, -2.0, 1.5, 0.8, 2.5, 0.5)

# Calculate price with different face value
price = gsw_price(1.0, 5.0, -2.0, 1.5, 0.8, 2.5, 0.5, face_value=1000.0)
```

# Notes
- Uses continuous compounding: P = F * exp(-r * t)
- Yield is converted from percentage to decimal for calculation
- Function is vectorizable: use `gsw_price.(maturities, β₀, β₁, β₂, β₃, τ₁, τ₂)`
"""
function gsw_price(maturity::Real, β₀::Real, β₁::Real, β₂::Real, β₃::Real, τ₁::Real, τ₂::Real; 
                   face_value::Real = 1.0)
    
    # Input validation
    if maturity <= 0
        throw(ArgumentError("Maturity must be positive, got $maturity"))
    end
    if face_value <= 0
        throw(ArgumentError("Face value must be positive, got $face_value"))
    end
    
    # Handle any missing values
    if any(ismissing, [β₀, β₁, β₂, β₃, τ₁, τ₂, maturity, face_value])
        return missing
    end
    
    # Get yield in percentage terms
    yield_percent = gsw_yield(maturity, β₀, β₁, β₂, β₃, τ₁, τ₂)
    
    if ismissing(yield_percent)
        return missing
    end
    
    # Convert to decimal and calculate price using continuous compounding
    continuous_rate = log(1.0 + yield_percent / 100.0)
    price = face_value * exp(-continuous_rate * maturity)
    
    return Float64(price)
end

# Method 1: Using GSWParameters struct
"""
    gsw_forward_rate(maturity₁, maturity₂, params::GSWParameters)

Calculate instantaneous forward rate between two maturities using GSW parameter struct.

# Arguments
- `maturity₁::Real`: Start maturity in years (must be positive and < maturity₂)
- `maturity₂::Real`: End maturity in years (must be positive and > maturity₁)
- `params::GSWParameters`: GSW parameter struct

# Returns
- `Float64`: Forward rate (decimal rate)

# Examples
```julia
params = GSWParameters(5.0, -2.0, 1.5, 0.8, 2.5, 0.5)
fwd_rate = gsw_forward_rate(2.0, 3.0, params)
```
"""
function gsw_forward_rate(maturity₁::Real, maturity₂::Real, params::GSWParameters)
    return gsw_forward_rate(maturity₁, maturity₂, _extract_params(params)...)
end

# Method 2: Using individual parameters
"""
    gsw_forward_rate(maturity₁, maturity₂, β₀, β₁, β₂, β₃, τ₁, τ₂)

Calculate instantaneous forward rate between two maturities using GSW parameters.

# Arguments
- `maturity₁::Real`: Start maturity in years (must be positive and < maturity₂)
- `maturity₂::Real`: End maturity in years (must be positive and > maturity₁)
- `β₀, β₁, β₂, β₃, τ₁, τ₂`: GSW parameters

# Returns
- `Float64`: Forward rate (decimal rate)

# Examples
```julia
# Calculate 1-year forward rate starting in 2 years
fwd_rate = gsw_forward_rate(2.0, 3.0, 5.0, -2.0, 1.5, 0.8, 2.5, 0.5)
```
"""
function gsw_forward_rate(maturity₁::Real, maturity₂::Real, 
    β₀::Real, β₁::Real, β₂::Real, β₃::Real, τ₁::Real, τ₂::Real)
    
    if maturity₁ <= 0 || maturity₂ <= maturity₁
        throw(ArgumentError("Must have 0 < maturity₁ < maturity₂, got maturity₁=$maturity₁, maturity₂=$maturity₂"))
    end
    
    # Handle missing values
    if any(ismissing, [β₀, β₁, β₂, β₃, τ₁, τ₂, maturity₁, maturity₂])
        return missing
    end
    
    # Get prices at both maturities
    p₁ = gsw_price(maturity₁, β₀, β₁, β₂, β₃, τ₁, τ₂)
    p₂ = gsw_price(maturity₂, β₀, β₁, β₂, β₃, τ₁, τ₂)
    
    if ismissing(p₁) || ismissing(p₂)
        return missing
    end
    
    # Calculate forward rate: f = -ln(P₂/P₁) / (T₂ - T₁)
    forward_rate_decimal = -log(p₂ / p₁) / (maturity₂ - maturity₁)
    
    # Convert to percentage
    return Float64(forward_rate_decimal)
end

# ------------------------------------------------------------------------------------------
# Vectorized convenience functions
# ------------------------------------------------------------------------------------------

"""
    gsw_yield_curve(maturities, params::GSWParameters)

Calculate yields for multiple maturities using GSW parameter struct.

# Arguments
- `maturities::AbstractVector{<:Real}`: Vector of maturities in years
- `params::GSWParameters`: GSW parameter struct

# Returns
- `Vector{Float64}`: Vector of yields in percent

# Examples
```julia
params = GSWParameters(5.0, -2.0, 1.5, 0.8, 2.5, 0.5)
maturities = [0.25, 0.5, 1, 2, 5, 10, 30]
yields = gsw_yield_curve(maturities, params)
```
"""
function gsw_yield_curve(maturities::AbstractVector{<:Real}, params::GSWParameters)
    return gsw_yield.(maturities, Ref(params))
end

"""
    gsw_yield_curve(maturities, β₀, β₁, β₂, β₃, τ₁, τ₂)

Calculate yields for multiple maturities using GSW parameters.

# Arguments
- `maturities::AbstractVector{<:Real}`: Vector of maturities in years
- `β₀, β₁, β₂, β₃, τ₁, τ₂`: GSW parameters

# Returns
- `Vector{Float64}`: Vector of yields in percent

# Examples
```julia
maturities = [0.25, 0.5, 1, 2, 5, 10, 30]
yields = gsw_yield_curve(maturities, 5.0, -2.0, 1.5, 0.8, 2.5, 0.5)
```
"""
function gsw_yield_curve(maturities::AbstractVector{<:Real}, β₀::Real, β₁::Real, β₂::Real, β₃::Real, τ₁::Real, τ₂::Real)
    return gsw_yield.(maturities, β₀, β₁, β₂, β₃, τ₁, τ₂)
end

"""
    gsw_price_curve(maturities, params::GSWParameters; face_value=1.0)

Calculate zero-coupon bond prices for multiple maturities using GSW parameter struct.

# Arguments
- `maturities::AbstractVector{<:Real}`: Vector of maturities in years
- `params::GSWParameters`: GSW parameter struct
- `face_value::Real`: Face value of bonds (default: 1.0)

# Returns
- `Vector{Float64}`: Vector of bond prices

# Examples
```julia
params = GSWParameters(5.0, -2.0, 1.5, 0.8, 2.5, 0.5)
maturities = [0.25, 0.5, 1, 2, 5, 10, 30]
prices = gsw_price_curve(maturities, params)
```
"""
function gsw_price_curve(maturities::AbstractVector{<:Real}, params::GSWParameters; face_value::Real = 1.0)
    return gsw_price.(maturities, Ref(params), face_value=face_value)
end

"""
    gsw_price_curve(maturities, β₀, β₁, β₂, β₃, τ₁, τ₂; face_value=1.0)

Calculate zero-coupon bond prices for multiple maturities using GSW parameters.

# Arguments
- `maturities::AbstractVector{<:Real}`: Vector of maturities in years
- `β₀, β₁, β₂, β₃, τ₁, τ₂`: GSW parameters
- `face_value::Real`: Face value of bonds (default: 1.0)

# Returns
- `Vector{Float64}`: Vector of bond prices

# Examples
```julia
maturities = [0.25, 0.5, 1, 2, 5, 10, 30]
prices = gsw_price_curve(maturities, 5.0, -2.0, 1.5, 0.8, 2.5, 0.5)
```
"""
function gsw_price_curve(maturities::AbstractVector{<:Real}, β₀::Real, β₁::Real, β₂::Real, β₃::Real, τ₁::Real, τ₂::Real; 
                        face_value::Real = 1.0)
    return gsw_price.(maturities, β₀, β₁, β₂, β₃, τ₁, τ₂, face_value=face_value)
end
# --------------------------------------------------------------------------------------------------




# --------------------------------------------------------------------------------------------------
# Return calculation functions
# ------------------------------------------------------------------------------------------

# Method 1: Using individual parameters
"""
    gsw_return(maturity, β₀_t, β₁_t, β₂_t, β₃_t, τ₁_t, τ₂_t, 
               β₀_t₋₁, β₁_t₋₁, β₂_t₋₁, β₃_t₋₁, τ₁_t₋₁, τ₂_t₋₁;
               frequency=:daily, return_type=:log)

Calculate bond return between two periods using GSW parameters.

Computes the return on a zero-coupon bond between two time periods by comparing
the price today (with aged maturity) to the price in the previous period.

# Arguments
- `maturity::Real`: Original maturity of the bond in years
- `β₀_t, β₁_t, β₂_t, β₃_t, τ₁_t, τ₂_t`: GSW parameters at time t
- `β₀_t₋₁, β₁_t₋₁, β₂_t₋₁, β₃_t₋₁, τ₁_t₋₁, τ₂_t₋₁`: GSW parameters at time t-1
- `frequency::Symbol`: Return frequency (:daily, :monthly, :annual)
- `return_type::Symbol`: :log for log returns, :arithmetic for simple returns

# Returns
- `Float64`: Bond return

# Examples
```julia
# Daily log return on 10-year bond
ret = gsw_return(10.0, 5.0, -2.0, 1.5, 0.8, 2.5, 0.5,  # today's params
                      4.9, -1.9, 1.4, 0.9, 2.4, 0.6)   # yesterday's params

# Monthly arithmetic return
ret = gsw_return(5.0, 5.0, -2.0, 1.5, 0.8, 2.5, 0.5,
                     4.9, -1.9, 1.4, 0.9, 2.4, 0.6,
                     frequency=:monthly, return_type=:arithmetic)
```
"""
function gsw_return(maturity::Real, 
                   β₀_t::Real, β₁_t::Real, β₂_t::Real, β₃_t::Real, τ₁_t::Real, τ₂_t::Real,
                   β₀_t₋₁::Real, β₁_t₋₁::Real, β₂_t₋₁::Real, β₃_t₋₁::Real, τ₁_t₋₁::Real, τ₂_t₋₁::Real;
                   frequency::Symbol = :daily,
                   return_type::Symbol = :log)
    
    # Input validation
    if maturity <= 0
        throw(ArgumentError("Maturity must be positive, got $maturity"))
    end
    
    valid_frequencies = [:daily, :monthly, :annual]
    if frequency ∉ valid_frequencies
        throw(ArgumentError("frequency must be one of $valid_frequencies, got $frequency"))
    end
    
    valid_return_types = [:log, :arithmetic]
    if return_type ∉ valid_return_types
        throw(ArgumentError("return_type must be one of $valid_return_types, got $return_type"))
    end
    
    # Handle missing values
    all_params = [β₀_t, β₁_t, β₂_t, β₃_t, τ₁_t, τ₂_t, β₀_t₋₁, β₁_t₋₁, β₂_t₋₁, β₃_t₋₁, τ₁_t₋₁, τ₂_t₋₁]
    if any(ismissing, all_params)
        return missing
    end
    
    # Determine time step based on frequency
    Δt = if frequency == :daily
        1/360  # Using 360-day year convention
    elseif frequency == :monthly  
        1/12
    elseif frequency == :annual
        1.0
    end
    
    # Calculate prices
    # P_t: Price today of bond with remaining maturity (maturity - Δt)
    aged_maturity = max(maturity - Δt, 0.001)  # Avoid zero maturity
    price_today = gsw_price(aged_maturity, β₀_t, β₁_t, β₂_t, β₃_t, τ₁_t, τ₂_t)
    
    # P_t₋₁: Price yesterday of bond with original maturity  
    price_previous = gsw_price(maturity, β₀_t₋₁, β₁_t₋₁, β₂_t₋₁, β₃_t₋₁, τ₁_t₋₁, τ₂_t₋₁)
    
    if ismissing(price_today) || ismissing(price_previous)
        return missing
    end
    
    # Calculate return
    if return_type == :log
        return log(price_today / price_previous)
    else  # arithmetic
        return (price_today - price_previous) / price_previous
    end
end


# Method 2: Using GSWParameters structs
"""
    gsw_return(maturity, params_t::GSWParameters, params_t₋₁::GSWParameters; frequency=:daily, return_type=:log)

Calculate bond return between two periods using GSW parameter structs.

# Arguments
- `maturity::Real`: Original maturity of the bond in years
- `params_t::GSWParameters`: GSW parameters at time t
- `params_t₋₁::GSWParameters`: GSW parameters at time t-1
- `frequency::Symbol`: Return frequency (:daily, :monthly, :annual)
- `return_type::Symbol`: :log for log returns, :arithmetic for simple returns

# Returns
- `Float64`: Bond return

# Examples
```julia
params_today = GSWParameters(5.0, -2.0, 1.5, 0.8, 2.5, 0.5)
params_yesterday = GSWParameters(4.9, -1.9, 1.4, 0.9, 2.4, 0.6)
ret = gsw_return(10.0, params_today, params_yesterday)
```
"""
function gsw_return(maturity::Real, params_t::GSWParameters, params_t₋₁::GSWParameters;
                   frequency::Symbol = :daily, return_type::Symbol = :log)
    return gsw_return(maturity, _extract_params(params_t)..., _extract_params(params_t₋₁)...,
                     frequency=frequency, return_type=return_type)
end




# Method 1: Using GSWParameters structs
"""
    gsw_excess_return(maturity, params_t::GSWParameters, params_t₋₁::GSWParameters; 
                      risk_free_maturity=0.25, frequency=:daily, return_type=:log)

Calculate excess return of a bond over the risk-free rate using GSW parameter structs.

# Arguments
- `maturity::Real`: Original maturity of the bond in years
- `params_t::GSWParameters`: GSW parameters at time t
- `params_t₋₁::GSWParameters`: GSW parameters at time t-1
- `risk_free_maturity::Real`: Maturity for risk-free rate calculation (default: 0.25 for 3-month)
- `frequency::Symbol`: Return frequency (:daily, :monthly, :annual)
- `return_type::Symbol`: :log for log returns, :arithmetic for simple returns

# Returns
- `Float64`: Excess return (bond return - risk-free return)

# Examples
```julia
params_today = GSWParameters(5.0, -2.0, 1.5, 0.8, 2.5, 0.5)
params_yesterday = GSWParameters(4.9, -1.9, 1.4, 0.9, 2.4, 0.6)
excess_ret = gsw_excess_return(10.0, params_today, params_yesterday)
```
"""
function gsw_excess_return(maturity::Real, params_t::GSWParameters, params_t₋₁::GSWParameters;
                          risk_free_maturity::Real = 0.25,
                          frequency::Symbol = :daily,
                          return_type::Symbol = :log)
    return gsw_excess_return(maturity, _extract_params(params_t)..., _extract_params(params_t₋₁)...,
                            risk_free_maturity=risk_free_maturity, frequency=frequency, return_type=return_type)
end

# Method 2: Using individual parameters
"""
    gsw_excess_return(maturity, β₀_t, β₁_t, β₂_t, β₃_t, τ₁_t, τ₂_t,
                      β₀_t₋₁, β₁_t₋₁, β₂_t₋₁, β₃_t₋₁, τ₁_t₋₁, τ₂_t₋₁;
                      risk_free_maturity=0.25, frequency=:daily, return_type=:log)

Calculate excess return of a bond over the risk-free rate.

# Arguments
- Same as `gsw_return` plus:
- `risk_free_maturity::Real`: Maturity for risk-free rate calculation (default: 0.25 for 3-month)

# Returns
- `Float64`: Excess return (bond return - risk-free return)
"""
function gsw_excess_return(maturity::Real,
                          β₀_t::Real, β₁_t::Real, β₂_t::Real, β₃_t::Real, τ₁_t::Real, τ₂_t::Real,
                          β₀_t₋₁::Real, β₁_t₋₁::Real, β₂_t₋₁::Real, β₃_t₋₁::Real, τ₁_t₋₁::Real, τ₂_t₋₁::Real;
                          risk_free_maturity::Real = 0.25,
                          frequency::Symbol = :daily,
                          return_type::Symbol = :log)
    
    # Calculate bond return
    bond_return = gsw_return(maturity, β₀_t, β₁_t, β₂_t, β₃_t, τ₁_t, τ₂_t,
                            β₀_t₋₁, β₁_t₋₁, β₂_t₋₁, β₃_t₋₁, τ₁_t₋₁, τ₂_t₋₁,
                            frequency=frequency, return_type=return_type)
    
    # Calculate risk-free return
    rf_return = gsw_return(risk_free_maturity, β₀_t, β₁_t, β₂_t, β₃_t, τ₁_t, τ₂_t,
                          β₀_t₋₁, β₁_t₋₁, β₂_t₋₁, β₃_t₋₁, τ₁_t₋₁, τ₂_t₋₁,
                          frequency=frequency, return_type=return_type)
    
    if ismissing(bond_return) || ismissing(rf_return)
        return missing
    end
    
    return bond_return - rf_return
end
# --------------------------------------------------------------------------------------------------



# --------------------------------------------------------------------------------------------------
# GSW DataFrame Wrapper Functions
# ------------------------------------------------------------------------------------------

"""
    add_yields!(df, maturities; validate=true)

Add yield calculations to a DataFrame containing GSW parameters.

Adds columns with yields for specified maturities using the Nelson-Siegel-Svensson 
model parameters in the DataFrame.

# Arguments
- `df::DataFrame`: DataFrame containing GSW parameters (must have columns: BETA0, BETA1, BETA2, BETA3, TAU1, TAU2)
- `maturities::Union{Real, AbstractVector{<:Real}}`: Maturity or vector of maturities in years
- `validate::Bool`: Whether to validate DataFrame structure (default: true)

# Returns
- `DataFrame`: Modified DataFrame with additional yield columns named `yield_Xy` (e.g., `yield_1y`, `yield_10y`)

# Examples
```julia
df = import_gsw_parameters()

# Add single maturity
add_yields!(df, 10.0)

# Add multiple maturities  
add_yields!(df, [1, 2, 5, 10, 30])

# Add with custom maturity (fractional)
add_yields!(df, [0.25, 0.5, 1.0])
```

# Notes
- Modifies the DataFrame in place
- Column names use format: `yield_Xy` where X is the maturity
- Handles missing parameter values gracefully
- Validates required columns are present
"""
function add_yields!(df::DataFrame, maturities::Union{Real, AbstractVector{<:Real}}; 
                    validate::Bool = true)
    
    if validate
        _validate_gsw_dataframe(df)
    end
    
    # Ensure maturities is a vector
    mat_vector = maturities isa Real ? [maturities] : collect(maturities)
    
    # Validate maturities
    if any(m -> m <= 0, mat_vector)
        throw(ArgumentError("All maturities must be positive"))
    end
    
    # Add yield columns using GSWParameters struct
    for maturity in mat_vector
        col_name = _maturity_to_column_name("yield", maturity)
        
        transform!(df, 
            AsTable([:BETA0, :BETA1, :BETA2, :BETA3, :TAU1, :TAU2]) => 
            ByRow(function(params)
                gsw_params = GSWParameters(params)
                if ismissing(gsw_params)
                    return missing
                else
                    return gsw_yield(maturity, gsw_params)
                end
            end) => col_name)
    end
    
    return df
end

"""
    add_prices!(df, maturities; face_value=100.0, validate=true)

Add zero-coupon bond price calculations to a DataFrame containing GSW parameters.

# Arguments
- `df::DataFrame`: DataFrame containing GSW parameters
- `maturities::Union{Real, AbstractVector{<:Real}}`: Maturity or vector of maturities in years
- `face_value::Real`: Face value of bonds (default: 100.0)
- `validate::Bool`: Whether to validate DataFrame structure (default: true)

# Returns
- `DataFrame`: Modified DataFrame with additional price columns named `price_Xy`

# Examples
```julia
df = import_gsw_parameters()

# Add prices for multiple maturities
add_prices!(df, [1, 5, 10])

# Add prices with different face value
add_prices!(df, 10.0, face_value=1000.0)
```
"""
function add_prices!(df::DataFrame, maturities::Union{Real, AbstractVector{<:Real}}; 
                    face_value::Real = 100.0, validate::Bool = true)
    
    if validate
        _validate_gsw_dataframe(df)
    end
    
    if face_value <= 0
        throw(ArgumentError("Face value must be positive, got $face_value"))
    end
    
    # Ensure maturities is a vector
    mat_vector = maturities isa Real ? [maturities] : collect(maturities)
    
    # Validate maturities
    if any(m -> m <= 0, mat_vector)
        throw(ArgumentError("All maturities must be positive"))
    end
    
    # Add price columns using GSWParameters struct
    for maturity in mat_vector
        col_name = _maturity_to_column_name("price", maturity)
        
        transform!(df, 
            AsTable([:BETA0, :BETA1, :BETA2, :BETA3, :TAU1, :TAU2]) => 
            ByRow(function(params)
                gsw_params = GSWParameters(params)
                if ismissing(gsw_params)
                    return missing
                else
                    return gsw_price(maturity, gsw_params, face_value=face_value)
                end
            end) => col_name)
    end
    
    return df
end

"""
    add_returns!(df, maturity; frequency=:daily, return_type=:log, validate=true)

Add bond return calculations to a DataFrame containing GSW parameters.

Calculates returns by comparing bond prices across time periods. Requires DataFrame 
to be sorted by date and contain consecutive time periods.

# Arguments
- `df::DataFrame`: DataFrame containing GSW parameters and dates (must have :date column)
- `maturity::Real`: Bond maturity in years
- `frequency::Symbol`: Return frequency (:daily, :monthly, :annual)
- `return_type::Symbol`: :log for log returns, :arithmetic for simple returns
- `validate::Bool`: Whether to validate DataFrame structure (default: true)

# Returns
- `DataFrame`: Modified DataFrame with return column named `ret_Xy_frequency` 
  (e.g., `ret_10y_daily`, `ret_5y_monthly`)

# Examples
```julia
df = import_gsw_parameters()

# Add daily log returns for 10-year bond
add_returns!(df, 10.0)

# Add monthly arithmetic returns for 5-year bond  
add_returns!(df, 5.0, frequency=:monthly, return_type=:arithmetic)
```

# Notes
- Requires DataFrame to be sorted by date
- First row will have missing return (no previous period)
- Uses lag of parameters to calculate returns properly
"""
function add_returns!(df::DataFrame, maturity::Real; 
                     frequency::Symbol = :daily, 
                     return_type::Symbol = :log,
                     validate::Bool = true)
    
    if validate
        _validate_gsw_dataframe(df, check_date=true)
    end
    
    if maturity <= 0
        throw(ArgumentError("Maturity must be positive, got $maturity"))
    end
    
    valid_frequencies = [:daily, :monthly, :annual]
    if frequency ∉ valid_frequencies
        throw(ArgumentError("frequency must be one of $valid_frequencies, got $frequency"))
    end
    
    valid_return_types = [:log, :arithmetic]
    if return_type ∉ valid_return_types
        throw(ArgumentError("return_type must be one of $valid_return_types, got $return_type"))
    end
    
    # Sort by date to ensure proper time series order
    sort!(df, :date)
    
    # Determine time step based on frequency
    time_step = if frequency == :daily
        Day(1)
    elseif frequency == :monthly
        Day(30)  # Approximate
    elseif frequency == :annual
        Day(360)  # Using 360-day year
    end
    
    # Create lagged parameter columns using PanelShift.jl
    param_cols = [:BETA0, :BETA1, :BETA2, :BETA3, :TAU1, :TAU2]
    for col in param_cols
        lag_col = Symbol("lag_$col")
        transform!(df, [:date, col] => 
                  ((dates, values) -> tlag(dates, values, time_step)) => 
                  lag_col)
    end
    
    # Calculate returns using current and lagged parameters
    col_name = Symbol(string(_maturity_to_column_name("ret", maturity)) * "_" * string(frequency))

    transform!(df,
        AsTable(vcat(param_cols, [Symbol("lag_$col") for col in param_cols])) =>
        ByRow(params -> begin
           current_params = GSWParameters(params.BETA0, params.BETA1, params.BETA2,
                                          params.BETA3, params.TAU1, params.TAU2)
           lagged_params = GSWParameters(params.lag_BETA0, params.lag_BETA1, params.lag_BETA2,
                                         params.lag_BETA3, params.lag_TAU1, params.lag_TAU2)
           if ismissing(current_params) || ismissing(lagged_params)
               missing
           else
               gsw_return(maturity, current_params, lagged_params,
                          frequency=frequency, return_type=return_type)
           end
       end
       ) => col_name)

    # Clean up temporary lagged columns
    select!(df, Not([Symbol("lag_$col") for col in param_cols]))
    
    # Reorder columns to put return column first (after date)
    if :date in names(df)
        other_cols = filter(col -> col ∉ [:date, col_name], names(df))
        select!(df, :date, col_name, other_cols...)
    end
    
    return df
end


"""
    add_excess_returns!(df, maturity; risk_free_maturity=0.25, frequency=:daily, return_type=:log, validate=true)

Add excess return calculations (bond return - risk-free return) to DataFrame.

# Arguments  
- Same as `add_returns!` plus:
- `risk_free_maturity::Real`: Maturity for risk-free rate (default: 0.25 for 3-month)

# Returns
- `DataFrame`: Modified DataFrame with excess return column named `excess_ret_Xy_frequency`
"""
function add_excess_returns!(df::DataFrame, maturity::Real; 
                            risk_free_maturity::Real = 0.25,
                            frequency::Symbol = :daily,
                            return_type::Symbol = :log,
                            validate::Bool = true)
                            
    if validate
        _validate_gsw_dataframe(df, check_date=true)
    end
    
    # Add regular returns first (will be cleaned up)
    temp_df = copy(df)
    add_returns!(temp_df, maturity, frequency=frequency, return_type=return_type, validate=false)
    add_returns!(temp_df, risk_free_maturity, frequency=frequency, return_type=return_type, validate=false)
    
    # Calculate excess returns
    bond_ret_col = Symbol(string(_maturity_to_column_name("ret", maturity)) * "_" * string(frequency))
    rf_ret_col = Symbol(string(_maturity_to_column_name("ret", risk_free_maturity)) * "_" * string(frequency))
    excess_col = Symbol(string(_maturity_to_column_name("excess_ret", maturity)) * "_" * string(frequency))
    
    transform!(temp_df, [bond_ret_col, rf_ret_col] => 
              ByRow((bond_ret, rf_ret) -> ismissing(bond_ret) || ismissing(rf_ret) ? missing : bond_ret - rf_ret) =>
              excess_col)
    
    # Add only the excess return column to original DataFrame
    df[!, excess_col] = temp_df[!, excess_col]
    
    return df
end

# ------------------------------------------------------------------------------------------
# Convenience functions
# ------------------------------------------------------------------------------------------

"""
    gsw_curve_snapshot(params::GSWParameters; maturities=[0.25, 0.5, 1, 2, 5, 10, 30])

Create a snapshot DataFrame of yields and prices for GSW parameters using parameter struct.

# Arguments
- `params::GSWParameters`: GSW parameter struct
- `maturities::AbstractVector`: Vector of maturities to calculate (default: standard curve)

# Returns  
- `DataFrame`: Contains columns :maturity, :yield, :price

# Examples
```julia
params = GSWParameters(5.0, -2.0, 1.5, 0.8, 2.5, 0.5)
curve = gsw_curve_snapshot(params)

# Custom maturities
curve = gsw_curve_snapshot(params, maturities=[0.5, 1, 3, 5, 7, 10, 20, 30])
```
"""
function gsw_curve_snapshot(params::GSWParameters; 
                           maturities::AbstractVector = [0.25, 0.5, 1, 2, 5, 10, 30])
    
    yields = gsw_yield_curve(maturities, params)
    prices = gsw_price_curve(maturities, params)
    
    return DataFrame(
        maturity = maturities,
        yield = yields,
        price = prices
    )
end

"""
    gsw_curve_snapshot(β₀, β₁, β₂, β₃, τ₁, τ₂; maturities=[0.25, 0.5, 1, 2, 5, 10, 30])

Create a snapshot DataFrame of yields and prices for a single date's GSW parameters.

# Arguments
- `β₀, β₁, β₂, β₃, τ₁, τ₂`: GSW parameters for a single date
- `maturities::AbstractVector`: Vector of maturities to calculate (default: standard curve)

# Returns  
- `DataFrame`: Contains columns :maturity, :yield, :price

# Examples
```julia
# Create yield curve snapshot
curve = gsw_curve_snapshot(5.0, -2.0, 1.5, 0.8, 2.5, 0.5)

# Custom maturities
curve = gsw_curve_snapshot(5.0, -2.0, 1.5, 0.8, 2.5, 0.5, 
                          maturities=[0.5, 1, 3, 5, 7, 10, 20, 30])
```
"""
function gsw_curve_snapshot(β₀::Real, β₁::Real, β₂::Real, β₃::Real, τ₁::Real, τ₂::Real;
                           maturities::AbstractVector = [0.25, 0.5, 1, 2, 5, 10, 30])
    
    yields = gsw_yield_curve(maturities, β₀, β₁, β₂, β₃, τ₁, τ₂)
    prices = gsw_price_curve(maturities, β₀, β₁, β₂, β₃, τ₁, τ₂)
    
    return DataFrame(
        maturity = maturities,
        yield = yields,
        price = prices
    )
end

# ------------------------------------------------------------------------------------------
# Internal helper functions  
# ------------------------------------------------------------------------------------------

"""
    _validate_gsw_dataframe(df; check_date=false)

Validate that DataFrame has required GSW parameter columns.
"""
function _validate_gsw_dataframe(df::DataFrame; check_date::Bool = false)
    required_cols = [:BETA0, :BETA1, :BETA2, :BETA3, :TAU1, :TAU2]
    missing_cols = setdiff(required_cols, propertynames(df))
    
    if !isempty(missing_cols)
        throw(ArgumentError("DataFrame missing required GSW parameter columns: $missing_cols"))
    end
    
    if check_date && :date ∉ propertynames(df)
        throw(ArgumentError("DataFrame must contain :date column for return calculations"))
    end
    
    if nrow(df) == 0
        throw(ArgumentError("DataFrame is empty"))
    end
end

"""
    _maturity_to_column_name(prefix, maturity)

Convert maturity to standardized column name.
"""
function _maturity_to_column_name(prefix::String, maturity::Real)
    # Handle fractional maturities nicely
    if maturity == floor(maturity)
        return Symbol("$(prefix)_$(Int(maturity))y")
    else
        # For fractional, use decimal but clean up trailing zeros
        maturity_str = string(maturity)
        maturity_str = replace(maturity_str, r"\.?0+$" => "")  # Remove trailing zeros
        return Symbol("$(prefix)_$(maturity_str)y")
    end
end
# --------------------------------------------------------------------------------------------------