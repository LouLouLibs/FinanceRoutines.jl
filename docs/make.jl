# Inside make.jl
push!(LOAD_PATH, "../src/")
# push!(LOAD_PATH, "./demo/", "./man/, ")

using FinanceRoutines
using Documenter

makedocs(
    format = Documenter.HTML(),
    sitename = "FinanceRoutines.jl",
    modules  = [FinanceRoutines],
    authors = "Erik Loualiche",
    pages=[
        "Home" => "index.md",
        "Manual" => [
            "man/wrds_guide.md",
            "man/yield_curve_gsw.md"
        ],
        "Demos" => [
            "demo/beta.md",
            "demo/wrds_advanced.md",
            "demo/crsp_siz_to_ciz.md"
        ],
        "Library" => [
            "lib/public.md",
            "lib/internals.md"
        ]
    ]
)

deploydocs(
    repo="github.com/louloulibs/FinanceRoutines.jl.git",
    target = "build",
)

deploydocs(;
    repo="github.com/louloulibs/FinanceRoutines.jl.git",
    target = "build",
    branch = "gh-pages",
)
