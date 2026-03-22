@testset "Event Study" begin

    import Dates: Date, Day
    import Statistics: mean

    # Build synthetic daily returns panel: 2 firms, 300 trading days
    dates = Date("2010-01-04"):Day(1):Date("2011-04-01")
    # Remove weekends for realistic trading calendar
    trading_days = filter(d -> Dates.dayofweek(d) <= 5, dates)
    trading_days = trading_days[1:300]  # exactly 300 days

    n = length(trading_days)
    df_ret = DataFrame(
        permno = vcat(fill(1, n), fill(2, n)),
        date = vcat(trading_days, trading_days),
        ret = vcat(0.001 .+ 0.01 .* randn(n), 0.0005 .+ 0.015 .* randn(n)),
        mktrf = vcat(repeat([0.0005 + 0.008 * randn()], n), repeat([0.0005 + 0.008 * randn()], n))
    )
    # Regenerate mktrf properly (same market for both firms on same date)
    mkt_returns = 0.0005 .+ 0.008 .* randn(n)
    df_ret.mktrf = vcat(mkt_returns, mkt_returns)

    # Inject a positive event: +5% abnormal return on event day for firm 1
    event_idx_firm1 = 270  # well within bounds for estimation window
    df_ret.ret[event_idx_firm1] += 0.05

    events = DataFrame(
        permno = [1, 2],
        event_date = [trading_days[event_idx_firm1], trading_days[280]]
    )

    # ---- Market-adjusted model ----
    @testset "Market-adjusted" begin
        result = event_study(events, df_ret; model=:market_adjusted)
        @test nrow(result) == 2
        @test "car" in names(result)
        @test "bhar" in names(result)
        @test "n_obs" in names(result)
        @test !ismissing(result.car[1])
        @test !ismissing(result.car[2])
        @test result.n_obs[1] == 21  # -10 to +10 inclusive
        # Firm 1 should have positive CAR (we injected +5%)
        @test result.car[1] > 0.03
    end

    # ---- Market model ----
    @testset "Market model" begin
        result = event_study(events, df_ret;
            model=:market_model,
            event_window=(-5, 5),
            estimation_window=(-250, -11))
        @test nrow(result) == 2
        @test !ismissing(result.car[1])
        @test result.n_obs[1] == 11  # -5 to +5
    end

    # ---- Mean-adjusted model ----
    @testset "Mean-adjusted" begin
        result = event_study(events, df_ret;
            model=:mean_adjusted,
            event_window=(-3, 3),
            estimation_window=(-200, -11))
        @test nrow(result) == 2
        @test !ismissing(result.car[1])
        @test result.n_obs[1] == 7  # -3 to +3
    end

    # ---- Edge cases ----
    @testset "Edge cases" begin
        # Entity not in returns
        events_missing = DataFrame(permno=[9999], event_date=[Date("2010-06-01")])
        result = event_study(events_missing, df_ret)
        @test ismissing(result.car[1])
        @test result.n_obs[1] == 0

        # Event too early (no estimation window)
        events_early = DataFrame(permno=[1], event_date=[trading_days[5]])
        result = event_study(events_early, df_ret)
        @test ismissing(result.car[1])

        # Invalid model
        @test_throws ArgumentError event_study(events, df_ret; model=:foo)
    end

end
