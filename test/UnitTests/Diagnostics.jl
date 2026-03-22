@testset "Data Quality Diagnostics" begin

    import Dates: Date

    # Create test data with known issues
    df = DataFrame(
        permno = [1, 1, 1, 2, 2, 2],
        date = [Date(2020,1,1), Date(2020,2,1), Date(2020,2,1),  # duplicate for permno 1
                Date(2020,1,1), Date(2020,3,1), Date(2020,4,1)],  # gap for permno 2
        ret = [0.05, missing, 0.03, -1.5, 0.02, 150.0],  # suspicious: -1.5, 150.0
        prc = [10.0, 20.0, 20.0, -5.0, 30.0, 40.0]  # negative price
    )
    allowmissing!(df, :ret)

    report = diagnose(df)

    # Basic structure
    @test report[:nrow] == 6
    @test report[:ncol] == 4

    # Missing rates
    @test haskey(report, :missing_rates)
    @test report[:missing_rates][:ret] ≈ 1/6
    @test report[:missing_rates][:permno] == 0.0

    # Duplicates
    @test haskey(report, :duplicate_keys)
    @test report[:duplicate_keys] == 1  # one duplicate (permno=1, date=2020-02-01)

    # Suspicious values
    @test haskey(report, :suspicious_values)
    @test length(report[:suspicious_values]) == 2  # extreme returns + negative prices
    @test any(s -> occursin("returns outside", s), report[:suspicious_values])
    @test any(s -> occursin("negative prices", s), report[:suspicious_values])

    # Test with custom columns / no ret/prc
    report2 = diagnose(df; ret_col=nothing, price_col=nothing)
    @test isempty(report2[:suspicious_values])

end
