# Import Yield Curve Data

Some utilities for working with Gürkaynak-Sack-Wright (GSW) yield curve data from the New York Fed and Nelson-Siegel-Svensson model calculations.
Note that some of the code was first written by hand and then reimplemented using AI; while I have tested some functions, you may want to do your own sanity checks. 

## Overview

This package provides tools to:
- Import daily GSW yield curve parameters from the Federal Reserve
- Calculate yields, prices, and returns using Nelson-Siegel-Svensson models
- Handle both 3-factor (Nelson-Siegel) and 4-factor (Svensson) model periods
- Work with time series of bond returns and risk premiums


## Installation

```julia
using FinanceRoutines; # Pkg.add(url="https://github.com/eloualiche/FinanceRoutines.jl")
```

## Quick Start

```julia
# Import GSW parameters from the Fed
df = import_gsw_parameters(date_range=(Date("1960-01-01"), Dates.today()) )

# Add yield calculations for multiple maturities
FinanceRoutines.add_yields!(df, [1, 2, 5, 10, 30])

# Add bond prices
FinanceRoutines.add_prices!(df, [1, 5, 10])

# Calculate daily returns for 10-year bonds
FinanceRoutines.add_returns!(df, 10.0, frequency=:daily, return_type=:log)
# Calculate excess returns over 3-month rate
FinanceRoutines.add_excess_returns!(df, 10.0, risk_free_maturity=0.25)
```


## Core Types

### GSWParameters

Structure to hold Nelson-Siegel-Svensson model parameters:

```julia
# 4-factor Svensson model
params = GSWParameters(5.0, -2.0, 1.5, 0.8, 2.5, 0.5)

# 3-factor Nelson-Siegel model (missing β₃, τ₂)
params_3f = GSWParameters(5.0, -2.0, 1.5, missing, 2.5, missing)

# From DataFrame row
params = GSWParameters(df[1, :])
```

## Core Functions

### Data Import

```julia
# Import all available data
df = import_gsw_parameters()

# Import specific date range
df = import_gsw_parameters(date_range=(Date("2010-01-01"), Date("2020-12-31")))
```

### Yield Calculations

```julia
# Single yield calculation
yield = gsw_yield(10.0, params)  # 10-year yield
yield = gsw_yield(10.0, 5.0, -2.0, 1.5, 0.8, 2.5, 0.5)  # Using individual parameters

# Yield curve
maturities = [0.25, 0.5, 1, 2, 5, 10, 30]
yields = gsw_yield_curve(maturities, params)
```

### Price Calculations

```julia
# Zero-coupon bond prices
price = gsw_price(10.0, params)  # 10-year zero price
price = gsw_price(10.0, params, face_value=100.0)  # Custom face value

# Price curve
prices = gsw_price_curve(maturities, params)
```

### Return Calculations

```julia
# Bond returns between two periods
params_today = GSWParameters(5.0, -2.0, 1.5, 0.8, 2.5, 0.5)
params_yesterday = GSWParameters(4.9, -1.9, 1.4, 0.9, 2.4, 0.6)

# Daily log return
ret = gsw_return(10.0, params_today, params_yesterday)

# Monthly arithmetic return
ret = gsw_return(10.0, params_today, params_yesterday, 
                frequency=:monthly, return_type=:arithmetic)

# Excess return over risk-free rate
excess_ret = gsw_excess_return(10.0, params_today, params_yesterday)
```

### Forward Rates

```julia
# 1-year forward rate starting in 2 years
fwd_rate = gsw_forward_rate(2.0, 3.0, params)
```

## DataFrame Operations

### Adding Calculations to DataFrames

```julia
# Add yields for multiple maturities
FinanceRoutines.add_yields!(df, [1, 2, 5, 10, 30])

# Add prices with custom face value
FinanceRoutines.add_prices!(df, [1, 5, 10], face_value=100.0)

# Add daily log returns
FinanceRoutines.add_returns!(df, 10.0, frequency=:daily, return_type=:log)

# Add monthly arithmetic returns
FinanceRoutines.add_returns!(df, 5.0, frequency=:monthly, return_type=:arithmetic)

# Add excess returns
FinanceRoutines.add_excess_returns!(df, 10.0, risk_free_maturity=0.25)
```

### Column Names

The package creates standardized column names:
- Yields: `yield_1y`, `yield_10y`, `yield_0.5y`
- Prices: `price_1y`, `price_10y`, `price_0.5y`
- Returns: `ret_10y_daily`, `ret_5y_monthly`
- Excess returns: `excess_ret_10y_daily`

## Convenience Functions

### Yield Curve Snapshots

```julia
# Create yield curve for a single date
curve = FinanceRoutines.gsw_curve_snapshot(params)
curve = FinanceRoutines.gsw_curve_snapshot(5.0, -2.0, 1.5, 0.8, 2.5, 0.5)

# Custom maturities
curve = FinanceRoutines.gsw_curve_snapshot(params, maturities=[1, 3, 5, 7, 10, 20, 30])
```

## Model Specifications

The package automatically handles two model types:

### 4-Factor Svensson Model
- Uses all 6 parameters: β₀, β₁, β₂, β₃, τ₁, τ₂
- More flexible yield curve shapes
- Used in recent periods

### 3-Factor Nelson-Siegel Model
- Uses 4 parameters: β₀, β₁, β₂, τ₁ (β₃=0, τ₂=τ₁)
- Simpler model specification
- Used in earlier periods or when data is missing

The package automatically detects which model to use based on available parameters.

## Missing Data Handling

- Automatically converts `-999` flag values to `missing`
- Gracefully handles periods with missing τ₂/β₃ parameters
- Propagates missing values through calculations appropriately

## Example Analysis

```julia
using DataFrames, Statistics

# Import data for 1970s and 1980s
df = import_gsw_parameters(date_range=(Date("1970-01-01"), Date("1989-12-31")))

# Add calculations
FinanceRoutines.add_yields!(df, 1)  # 1-year yields
FinanceRoutines.add_prices!(df, 1)  # 1-year prices  
FinanceRoutines.add_returns!(df, 2, frequency=:daily, return_type=:log)  # 2-year daily returns

# Analyze by decade
transform!(df, :date => (x -> year.(x) .÷ 10 * 10) => :decade)

# Summary statistics
stats = combine(
    groupby(df, :decade),
    :yield_1y => (x -> mean(skipmissing(x))) => :mean_yield,
    :yield_1y => (x -> std(skipmissing(x))) => :vol_yield,
    :ret_2y_daily => (x -> mean(skipmissing(x))) => :mean_return,
    :ret_2y_daily => (x -> std(skipmissing(x))) => :vol_return
)
```


## API
## Data Source

GSW yield curve parameters are downloaded from the Federal Reserve Economic Data (FRED):
- URL: https://www.federalreserve.gov/data/yield-curve-tables/feds200628.csv
- Updated daily
- Historical data available from 1961

## References

- Gürkaynak, R. S., B. Sack, and J. H. Wright (2007). "The U.S. Treasury yield curve: 1961 to the present." Journal of Monetary Economics 54(8), 2291-2304.
- Nelson, C. R. and A. F. Siegel (1987). "Parsimonious modeling of yield curves." Journal of Business 60(4), 473-489.
- Svensson, L. E. (1994). "Estimating and interpreting forward interest rates: Sweden 1992-1994." NBER Working Paper No. 4871.















