# OTHER FUNCTIONS TO WORK WITH BONDS ... NOT DIRECTLY RELATED TO TREASURIES ...
"""
    bond_yield_excel(settlement, maturity, rate, price, redemption; 
                     frequency=2, basis=0) -> Float64

Calculate the yield to maturity of a bond using Excel-compatible YIELD function interface.

This function provides an Excel-compatible API for calculating bond yield to maturity,
matching the behavior and parameter conventions of Excel's `YIELD()` function. It
internally converts the date-based inputs to the time-to-maturity format required
by the underlying `bond_yield()` function.

# Arguments
- `settlement::Date`: Settlement date of the bond (when the bond is purchased)
- `maturity::Date`: Maturity date of the bond (when principal is repaid)  
- `rate::Real`: Annual coupon rate as a decimal (e.g., 0.0575 for 5.75%)
- `price::Real`: Bond's price per 100 of face value
- `redemption::Real`: Redemption value per 100 of face value (typically 100)

# Keyword Arguments  
- `frequency::Integer=2`: Number of coupon payments per year
  - `1` = Annual
  - `2` = Semiannual (default)
  - `4` = Quarterly
- `basis::Integer=0`: Day count basis for calculating time periods
  - `0` = 30/360 (default)
  - `1` = Actual/actual
  - `2` = Actual/360  
  - `3` = Actual/365
  - `4` = European 30/360

# Returns
- `Float64`: Annual yield to maturity as a decimal (e.g., 0.065 for 6.5%)

# Excel Compatibility
This function replicates Excel's `YIELD(settlement, maturity, rate, price, redemption, frequency, basis)` 
function with identical parameter meanings and calculation methodology.

# Example (Excel Documentation Case)
```julia
using Dates

# Excel example data:
settlement = Date(2008, 2, 15)    # 15-Feb-08 Settlement date
maturity = Date(2016, 11, 15)     # 15-Nov-16 Maturity date  
rate = 0.0575                     # 5.75% Percent coupon
price = 95.04287                  # Price per 100 face value
redemption = 100.0                # 100 Redemption value
frequency = 2                     # Semiannual frequency
basis = 0                         # 30/360 basis

# Calculate yield (matches Excel YIELD function)
ytm = bond_yield_excel(settlement, maturity, rate, price, redemption, 
                       frequency=frequency, basis=basis)
# Result: 0.065 (6.5%)

# Equivalent Excel formula: =YIELD(A2,A3,A4,A5,A6,A7,A8)
# where cells contain the values above
```

# Additional Examples
```julia
# Corporate bond with quarterly payments
settlement = Date(2024, 1, 15)
maturity = Date(2029, 1, 15)
ytm = bond_yield_excel(settlement, maturity, 0.045, 98.50, 100.0, 
                       frequency=4, basis=1)

# Government bond with annual payments, actual/365 basis
ytm = bond_yield_excel(Date(2024, 3, 1), Date(2034, 3, 1), 
                       0.0325, 102.25, 100.0, frequency=1, basis=3)
```

# Notes
- Settlement date must be before maturity date
- Price and redemption are typically quoted per 100 of face value
- Uses actual coupon dates and the specified day-count basis, matching Excel's computation
- Results should match Excel's YIELD function within numerical precision

# Throws
- `ArgumentError`: If settlement ≥ maturity date
- Convergence errors from underlying numerical root-finding

See also: [`bond_yield`](@ref)
"""
function bond_yield_excel(
    settlement::Date, maturity::Date, rate::Real, price::Real, redemption::Real;
    frequency = 2, basis = 0)

    if settlement >= maturity
        throw(ArgumentError("Settlement ($settlement) must be before maturity ($maturity)"))
    end

    # Compute coupon schedule by working backwards from maturity
    period_months = div(12, frequency)

    # Find next coupon date after settlement
    next_coupon = maturity
    while next_coupon - Month(period_months) > settlement
        next_coupon -= Month(period_months)
    end
    prev_coupon = next_coupon - Month(period_months)

    # Count remaining coupons (from next_coupon to maturity, inclusive)
    N = 0
    d = next_coupon
    while d <= maturity
        N += 1
        d += Month(period_months)
    end

    # Day count fractions using the specified basis
    A   = _day_count_days(prev_coupon, settlement, basis)   # accrued days
    E   = _day_count_days(prev_coupon, next_coupon, basis)   # days in coupon period
    DSC = E - A                                              # Excel defines DSC = E - A to ensure consistency

    α = DSC / E   # fraction of period until next coupon
    coupon = redemption * rate / frequency

    # Excel's YIELD pricing formula
    function price_from_yield(y)
        if y <= 0
            return Inf
        end

        dr = y / frequency

        if N == 1
            # Special case: single remaining coupon
            return (redemption + coupon) / (1 + α * dr) - coupon * A / E
        end

        # General case: N > 1 coupons
        # PV of coupon annuity: ∑(k=1..N) coupon/(1+dr)^(k-1+α) = coupon*(1+dr)^(1-α)/dr * [1-(1+dr)^(-N)]
        pv_coupons = coupon * (1 + dr)^(1 - α) * (1 - (1 + dr)^(-N)) / dr
        # PV of redemption
        pv_redemption = redemption / (1 + dr)^(N - 1 + α)
        # Subtract accrued interest
        return pv_coupons + pv_redemption - coupon * A / E
    end

    price_diff(y) = price_from_yield(y) - price

    try
        return Roots.find_zero(price_diff, (1e-6, 2.0), Roots.Brent())
    catch e
        if isa(e, ArgumentError) && occursin("not a bracketing interval", sprint(showerror, e))
            @warn "Brent failed: falling back to Order1" exception=e
            return Roots.find_zero(price_diff, rate, Roots.Order1())
        else
            rethrow(e)
        end
    end
end

"""
    bond_yield(price, face_value, coupon_rate, years_to_maturity, frequency; 
               method=:brent, bracket=(0.001, 1.0)) -> Float64

Calculate the yield to maturity (YTM) of a bond given its market price and characteristics.

This function uses numerical root-finding to determine the discount rate that equates the 
present value of all future cash flows (coupon payments and principal repayment) to the 
current market price of the bond. The calculation properly handles bonds with fractional 
periods remaining until maturity and accounts for accrued interest.

# Arguments
- `price::Real`: Current market price of the bond
- `face_value::Real`: Par value or face value of the bond (principal amount)
- `coupon_rate::Real`: Annual coupon rate as a decimal (e.g., 0.05 for 5%)
- `years_to_maturity::Real`: Time to maturity in years (can be fractional)
- `frequency::Integer`: Number of coupon payments per year (e.g., 2 for semi-annual, 4 for quarterly)

# Keyword Arguments
- `method::Symbol=:brent`: Root-finding method (currently only :brent is implemented)
- `bracket::Tuple{Float64,Float64}=(0.001, 1.0)`: Initial bracket for yield search as (lower_bound, upper_bound)

# Returns
- `Float64`: The yield to maturity as an annual rate (decimal form)

# Algorithm Details
The function calculates bond price using the standard present value formula:
- For whole coupon periods: discounts each coupon payment to present value
- For fractional periods: applies fractional discounting and adjusts for accrued interest
- Handles the special case where yield approaches zero (no discounting)
- Uses the Brent method for robust numerical root-finding

The price calculation accounts for:
1. Present value of remaining coupon payments
2. Present value of principal repayment
3. Accrued interest adjustments for fractional periods

# Examples
```julia
# Calculate YTM for a 5% annual coupon bond, 1000 face value, 3.5 years to maturity,
# semi-annual payments, currently priced at 950
ytm = bond_yield(950, 1000, 0.05, 3.5, 2)

# 10-year quarterly coupon bond
ytm = bond_yield(1050, 1000, 0.06, 10.0, 4)

# Bond very close to maturity (0.25 years)
ytm = bond_yield(998, 1000, 0.04, 0.25, 2)
```

# Notes
- The yield returned is the effective annual rate compounded at the specified frequency
- For bonds trading at a premium (price > face_value), expect YTM < coupon_rate
- For bonds trading at a discount (price < face_value), expect YTM > coupon_rate
- The function assumes the next coupon payment occurs exactly one period from now
- Requires the `Roots.jl` package for numerical root-finding

# Throws
- May throw convergence errors if the root-finding algorithm fails to converge
- Will return `Inf` for invalid yields (≤ 0)

See also: [`bond_yield_excel`](@ref)
"""
function bond_yield(price, face_value, coupon_rate, years_to_maturity, frequency; 
                   method=:brent, bracket=(0.001, 1.0))
    
    total_periods = years_to_maturity * frequency
    whole_periods = floor(Int, total_periods)  # Complete coupon periods
    fractional_period = total_periods - whole_periods  # Partial period
    
    coupon_payment = (face_value * coupon_rate) / frequency
    
    function price_diff(y)
        if y <= 0
            return Inf
        end
        
        discount_rate = y / frequency
        calculated_price = 0.0
        
        if discount_rate == 0
            # Zero yield case
            calculated_price = coupon_payment * whole_periods + face_value
            if fractional_period > 0
                # Add accrued interest for partial period
                calculated_price += coupon_payment * fractional_period
            end
        else
            # Present value of whole coupon payments
            if whole_periods > 0
                pv_coupons = coupon_payment * (1 - (1 + discount_rate)^(-whole_periods)) / discount_rate
                calculated_price += pv_coupons / (1 + discount_rate)^fractional_period
            end
            
            # Present value of principal (always discounted by full period)
            pv_principal = face_value / (1 + discount_rate)^total_periods
            calculated_price += pv_principal
            
            # Subtract accrued interest (what buyer owes seller)
            if fractional_period > 0
                accrued_interest = coupon_payment * fractional_period
                calculated_price -= accrued_interest
            end
        end
        
        return calculated_price - price
    end

    try
        return Roots.find_zero(price_diff, bracket, Roots.Brent())
    catch e
        if isa(e, ArgumentError) && occursin("not a bracketing interval", sprint(showerror, e))
            # Fall back to a derivative-free method using an initial guess
            @warn "Brent failed: falling back to Order1" exception=e
            return Roots.find_zero(price_diff, 0.02, Roots.Order1())
        else
            rethrow(e)
        end
    end

end


"""
    _day_count_days(d1, d2, basis) -> Int

Count the number of days between two dates using the specified day-count convention.
Used internally for bond yield calculations.

- `basis=0`: 30/360 (US)
- `basis=1`: Actual/actual
- `basis=2`: Actual/360
- `basis=3`: Actual/365
- `basis=4`: European 30/360
"""
function _day_count_days(d1::Date, d2::Date, basis::Int)
    if basis == 0  # 30/360 US
        day1, mon1, yr1 = Dates.day(d1), Dates.month(d1), Dates.year(d1)
        day2, mon2, yr2 = Dates.day(d2), Dates.month(d2), Dates.year(d2)
        if day1 == 31; day1 = 30; end
        if day2 == 31 && day1 >= 30; day2 = 30; end
        return 360 * (yr2 - yr1) + 30 * (mon2 - mon1) + (day2 - day1)
    elseif basis == 4  # European 30/360
        day1, mon1, yr1 = Dates.day(d1), Dates.month(d1), Dates.year(d1)
        day2, mon2, yr2 = Dates.day(d2), Dates.month(d2), Dates.year(d2)
        if day1 == 31; day1 = 30; end
        if day2 == 31; day2 = 30; end
        return 360 * (yr2 - yr1) + 30 * (mon2 - mon1) + (day2 - day1)
    else  # basis 1, 2, 3: actual days
        return Dates.value(d2 - d1)
    end
end

function _date_difference(start_date, end_date; basis=1)
    days = _day_count_days(start_date, end_date, basis)
    if basis == 0
        return days / 360
    elseif basis == 1
        return days / 365.25
    elseif basis == 2
        return days / 360
    elseif basis == 3
        return days / 365
    else
        error("Invalid basis: $basis")
    end
end
# --------------------------------------------------------------------------------------------------

