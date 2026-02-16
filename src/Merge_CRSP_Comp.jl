#! /usr/bin/env julia
# --------------------------------------------------------------------------------------------------
# Merge_CRSP_Comp.jl

# Collection of functions that get the link files from crsp/compustat
# --------------------------------------------------------------------------------------------------


# --------------------------------------------------------------------------------------------------
# List of exported functions
# export link_Funda
# export link_MSF
# --------------------------------------------------------------------------------------------------



# --------------------------------------------------------------------------------------------------
"""
    import_ccm_link(wrds_conn::Connection)
    import_ccm_link(; user::String="", password::String="")

Import and process the CRSP/Compustat Merged (CCM) linking table from WRDS.

Downloads the CCM linking table that maps between CRSP's PERMNO and Compustat's GVKEY 
identifiers, enabling cross-database research between CRSP and Compustat datasets.

# Arguments
## Method 1
- `wrds_conn::Connection`: An established database connection to WRDS PostgreSQL server

## Method 2 (Keyword Arguments)
- `user::String=""`: WRDS username. If empty, attempts to use default connection via `open_wrds_pg()`
- `password::String=""`: WRDS password. Only used if `user` is provided

# Returns
- `DataFrame`: Processed linking table with the following columns:
  - `:gvkey`: Compustat's permanent company identifier (converted to Int)
  - `:permno`: CRSP's permanent security identifier (renamed from `:lpermno`)
  - `:linkdt`: Start date of the link validity period
  - `:linkenddt`: End date of the link validity period (missing values set to today's date)
  - `:linkprim`: Primary link marker (String3 type)
  - `:liid`: IID of the linked CRSP issue (String3 type)
  - `:linktype`: Type of link (String3 type)
  - Additional columns from the original CRSP.CCMXPF_LNKHIST table

# Processing Steps
1. Downloads the complete CRSP.CCMXPF_LNKHIST table from WRDS
2. Converts integer columns to proper Int type (handling missing values)
3. Parses GVKEY from string to integer format
4. Converts link descriptors to String3 type for efficiency
5. Filters to keep only primary links:
   - Link types: "LU" (US companies), "LC" (Canadian), "LS" (ADRs)
   - Link primary: "P" (Primary) or "C" (Primary after CUSIP link)
6. Sets missing end dates to today's date (assuming link is still active)
7. Renames `:lpermno` to `:permno` for consistency

# Examples
```julia
# Using existing connection
wrds_conn = open_wrds_pg("myusername", "mypassword")
df_linktable = import_ccm_link(wrds_conn)

# Using automatic connection
df_linktable = import_ccm_link()

# Using credentials directly
df_linktable = import_ccm_link(user="myusername", password="mypassword")
```

# Notes
- Requires active WRDS subscription and PostgreSQL access
- Only primary security links are retained (see WRDS CCM documentation for link type details)
- Missing link end dates are interpreted as currently active links
- The function uses `@p` macro for pipeline operations and `@debug` for logging
- All date columns (`:linkdt`, `:linkenddt`) and `:permno` are set as non-missing

# References
- WRDS CCM Database documentation: https://wrds-www.wharton.upenn.edu/pages/support/manuals-and-overviews/crsp/crspcompustat-merged-ccm/

See also: [`link_Funda`](@ref), [`link_MSF`](@ref), [`open_wrds_pg`](@ref)
"""
function import_ccm_link(wrds_conn::Connection)

    # Download link table
    postgre_query_linktable = """
        SELECT *
            FROM crsp.ccmxpf_lnkhist
    """
    res_q_linktable = execute(wrds_conn, postgre_query_linktable)

    df_linktable = DataFrame(columntable(res_q_linktable))
    transform!(df_linktable, names(df_linktable, check_integer.(eachcol(df_linktable))) .=>
        (x->convert.(Union{Missing, Int}, x));
        renamecols = false);
    transform!(df_linktable, :gvkey => ByRow(x->parse(Int, x)) => :gvkey);
    transform!(df_linktable, [:linkprim, :liid, :linktype] .=> ByRow(String3), renamecols=false)

    # Prepare the table
    @p df_linktable |> filter!(_.linktype ∈ ("LU", "LC", "LS") && _.linkprim ∈ ("P", "C") )
    df_linktable[ ismissing.(df_linktable.linkenddt), :linkenddt ] .= Dates.today();
    disallowmissing!(df_linktable, [:linkdt, :linkenddt, :lpermno]);
    @debug "renaming lpermno in linktable to permno"
    rename!(df_linktable, :lpermno => :permno);

    return df_linktable
end


# when there are no connections establisheds
function import_ccm_link(;
    user::String = "", password::String = "")

    with_wrds_connection(user=user, password=password) do conn
        import_ccm_link(conn)
    end
end
# --------------------------------------------------------------------------------------------------


# --------------------------------------------------------------------------------------------------
"""
    link_Funda(df_linktable::DataFrame, df_funda::DataFrame, variables::Vector{Symbol}=Symbol[])

Link Compustat fundamentals data with CRSP security identifiers using a linking table.

This function performs a temporal join between Compustat fundamental data and a security 
linking table (typically CRSP/Compustat Merged Database linking table) to assign PERMNO 
identifiers to Compustat records based on valid date ranges.

# Arguments
- `df_linktable::DataFrame`: Linking table containing the mapping between GVKEY and PERMNO 
  identifiers. Must include columns:
  - `:gvkey`: Compustat's permanent company identifier
  - `:linkdt`: Start date of the link validity period
  - `:linkenddt`: End date of the link validity period
  - `:permno`: CRSP's permanent security identifier
  - Additional columns that will be removed: `:linkprim`, `:liid`, `:linktype`

- `df_funda::DataFrame`: Compustat fundamentals data. Must include columns:
  - `:gvkey`: Compustat's permanent company identifier
  - `:datadate`: Date of the fundamental data observation

- `variables::Vector{Symbol}=Symbol[]`: which existing variables in the dataframe do we want to keep

# Returns
- `DataFrame`: Joined dataset containing all columns from `df_funda` plus `:permno` from 
  the linking table. The following columns from the linking table are excluded from output:
  `:gvkey_1`, `:linkprim`, `:liid`, `:linktype`, `:linkdt`, `:linkenddt`

# Details
The function performs an inner join where:
1. Records are matched on `:gvkey`
2. The `:datadate` from fundamentals must fall within the valid link period 
   `[linkdt, linkenddt]` from the linking table

This ensures that each fundamental data observation is matched with the correct PERMNO 
based on the security's identification history, handling cases where companies change 
their CRSP identifiers over time.

# Examples
```julia
# Load linking table and fundamentals data
df_linktable = load_ccm_links()
df_funda = load_compustat_funda()

# Link the datasets
linked_data = link_Funda(df_linktable, df_funda)
# Result contains fundamental data with PERMNO identifiers added
```

# Notes
Uses FlexiJoins.innerjoin for temporal joining capabilities
Only records with valid links during the observation date are retained
"""
function link_Funda(df_linktable::DataFrame, df_funda::DataFrame,
    variables::Vector{Symbol}=Symbol[])

    funda_link_permno = FlexiJoins.innerjoin(
        (select(df_funda, :gvkey, :datadate), df_linktable),
        by_key(:gvkey) & by_pred(:datadate, ∈, x->x.linkdt..x.linkenddt) )
    
    variables_to_remove = vcat(:gvkey_1,
        setdiff([:linkprim, :liid, :linktype, :linkdt, :linkenddt], variables) )

    select!(funda_link_permno,
        Not(variables_to_remove))

    return funda_link_permno

end
# ------------------------------------------------------------------------------------------



# ------------------------------------------------------------------------------------------
"""
    link_MSF(df_linktable::DataFrame, df_msf::DataFrame; variables::Vector{Symbol}=Symbol[])

Link CRSP monthly stock file data with Compustat identifiers using a linking table.

This function performs a temporal join to add GVKEY (Compustat identifiers) to CRSP monthly 
stock data, enabling cross-database analysis between CRSP and Compustat datasets.

# Arguments
- `df_linktable::DataFrame`: Linking table containing the mapping between PERMNO and GVKEY 
  identifiers. Must include columns:
  - `:permno`: CRSP's permanent security identifier
  - `:gvkey`: Compustat's permanent company identifier
  - `:linkdt`: Start date of the link validity period
  - `:linkenddt`: End date of the link validity period

- `df_msf::DataFrame`: CRSP monthly stock file data. Must include columns:
  - `:permno`: CRSP's permanent security identifier
  - `:date`: Date of the stock observation
  - Additional columns as specified in `variables` (if any)

# Keyword Arguments
- `variables::Vector{Symbol}=Symbol[]`: Optional list of additional columns to retain from 
  the linking process. Only columns that exist in both datasets will be kept.

# Returns
- `DataFrame`: Original CRSP data with GVKEY identifiers added where valid links exist. 
  Includes:
  - All original columns from `df_msf`
  - `:gvkey`: Compustat identifier (where available)
  - `:datey`: Year extracted from the `:date` column
  - Any additional columns specified in `variables` that exist in the joined data

# Details
The function performs a two-step process:
1. **Inner join with temporal filtering**: Matches CRSP records to the linking table where 
   the stock date falls within the valid link period `[linkdt, linkenddt]`
2. **Left join back to original data**: Ensures all original CRSP records are retained, 
   with GVKEY values added only where valid links exist

Records with missing GVKEY values after the initial join are filtered out before the 
merge-back step, ensuring only valid links are propagated.

# Examples
```julia
# Load data
df_linktable = load_ccm_links()
df_msf = load_crsp_monthly()

# Basic linking
linked_msf = link_MSF(df_linktable, df_msf)

# Include additional variables from the linking table
linked_msf = link_MSF(df_linktable, df_msf, variables=[:linkprim, :linktype])
```
"""
function link_MSF(df_linktable::DataFrame, df_msf::DataFrame;
    variables::Vector{Symbol}=Symbol[])

# Merge with CRSP
    df_msf_linked = FlexiJoins.innerjoin(
        (df_msf, df_linktable),
        by_key(:permno) & by_pred(:date, ∈, x->x.linkdt..x.linkenddt)
    )
    @p df_msf_linked |> filter!(.!ismissing.(_.gvkey))
    col_keep = vcat([:date, :permno, :gvkey], intersect(variables, propertynames(df_msf_linked))) |> unique
    select!(df_msf_linked, col_keep)
    
# merge this back
    df_msf_linked = leftjoin(df_msf, df_msf_linked, on = [:date, :permno], source="_merge")
    transform!(df_msf_linked, :date => ByRow(year) => :datey)
    select!(df_msf_linked, Not(:_merge))


    return df_msf_linked
end
# ------------------------------------------------------------------------------------------



# ------------------------------------------------------------------------------------------
# function link_ccm(df_linktable, df_msf, df_funda)

# # ccm
#     df_ccm = leftjoin(
#         df_msf_merged, df_funda,
#         on = [:gvkey, :datey], matchmissing = :notequal)

#     if save
#         CSV.write("./tmp/ccm.csv.gz", df_ccm, compress=true)
#     end

# end
# ------------------------------------------------------------------------------------------
