# --------------------------------------------------------------------------------------------------

# ImportFamaFrench.jl

# Collection of functions that import
#  financial data from Ken French's website into julia
# --------------------------------------------------------------------------------------------------



# --------------------------------------------------------------------------------------------------
# Shared helper: download a Ken French zip and extract the CSV entry
# --------------------------------------------------------------------------------------------------
function _download_ff_zip(url)
    http_response = Downloads.download(url)
    z = ZipFile.Reader(http_response)
    csv_file = filter(x -> match(r".*csv", lowercase(x.name)) !== nothing, z.files)[1]
    return (z, csv_file)
end


# --------------------------------------------------------------------------------------------------
"""
    import_FF3(;frequency::Symbol=:monthly) -> DataFrame

Import Fama-French 3-factor model data directly from Ken French's data library.

Downloads and parses the Fama-French research data factors (market risk premium,
size factor, value factor, and risk-free rate) at the specified frequency.

# Arguments
- `frequency::Symbol=:monthly`: Data frequency to import. Options are:
  - `:monthly` - Monthly factor returns (default)
  - `:annual` - Annual factor returns
  - `:daily` - Daily factor returns

# Returns
- `DataFrame`: Fama-French 3-factor data with columns:
  - **Monthly/Annual**: `datem`/`datey`, `mktrf`, `smb`, `hml`, `rf`
  - **Daily**: `date`, `mktrf`, `smb`, `hml`, `rf`

Where:
- `mktrf`: Market return minus risk-free rate (market risk premium)
- `smb`: Small minus big (size factor)
- `hml`: High minus low (value factor)
- `rf`: Risk-free rate

# Examples
```julia
# Import monthly data (default)
monthly_ff = import_FF3()

# Import annual data
annual_ff = import_FF3(frequency=:annual)

# Import daily data
daily_ff = import_FF3(frequency=:daily)
```

# Notes
- Data is sourced directly from Kenneth French's data library at Dartmouth
- Monthly and annual data excludes the daily/monthly breakdowns respectively
- Date formats are automatically parsed to appropriate Julia date types
- Missing values are filtered out from the datasets
- Requires internet connection to download data

# Data Source
Kenneth R. French Data Library: https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/data_library.html
"""
function import_FF3(;frequency::Symbol=:monthly)
    url_mth_yr = "https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/ftp/F-F_Research_Data_Factors_CSV.zip"
    url_daily  = "https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/ftp/F-F_Research_Data_Factors_daily_CSV.zip"
    col_types  = [String7, Float64, Float64, Float64, Float64]

    return _import_ff_factors(frequency, url_mth_yr, url_daily, col_types,
        col_names_monthly = [:datem, :mktrf, :smb, :hml, :rf],
        col_names_annual  = [:datey, :mktrf, :smb, :hml, :rf],
        col_names_daily   = [:date, :mktrf, :smb, :hml, :rf])
end
# --------------------------------------------------------------------------------------------------


# --------------------------------------------------------------------------------------------------
# Shared import logic for FF3/FF5/momentum — handles all three frequencies
# --------------------------------------------------------------------------------------------------
function _import_ff_factors(frequency::Symbol, url_mth_yr, url_daily, col_types;
    col_names_monthly, col_names_annual, col_names_daily)

    if frequency == :annual

        z, csv_file = _download_ff_zip(url_mth_yr)
        df = copy(_parse_ff_annual(csv_file, types=col_types, col_names=col_names_annual))
        close(z)
        return df

    elseif frequency == :monthly

        z, csv_file = _download_ff_zip(url_mth_yr)
        df = copy(_parse_ff_monthly(csv_file, types=col_types, col_names=col_names_monthly))
        close(z)
        transform!(df, col_names_monthly[1] => ByRow(x -> MonthlyDate(x, "yyyymm")) => col_names_monthly[1])
        return df

    elseif frequency == :daily

        z, csv_file = _download_ff_zip(url_daily)
        df = copy(CSV.File(csv_file, header=4, footerskip=1) |> DataFrame)
        close(z)
        rename!(df, col_names_daily)
        date_col = col_names_daily[1]
        val_col = col_names_daily[2]
        subset!(df, date_col => ByRow(!ismissing), val_col => ByRow(!ismissing))
        transform!(df, :date => ByRow(x -> Date(string(x), "yyyymmdd")) => :date)
        return df

    else
        error("Frequency $frequency not known. Options are :daily, :monthly, or :annual")
    end
end
# --------------------------------------------------------------------------------------------------


# --------------------------------------------------------------------------------------------------
function _parse_ff_annual(zip_file; types=nothing,
    col_names=[:datey, :mktrf, :smb, :hml, :rf])

    lines = String[]
    found_annual = false

    # Read all lines from the zip file entry
    file_lines = split(String(read(zip_file)), '\n')

    for line in file_lines
        if occursin(r"Annual Factors", line)
            found_annual = true
            continue
        end

        if found_annual
            # Skip the header line that comes after "Annual Factors"
            if occursin(r"Mkt-RF|SMB|HML|RF", line)
                continue
            end

            if occursin(r"^\s*$", line) || occursin(r"[A-Za-z]{3,}", line[1:min(10, length(line))])
                if !occursin(r"^\s*$", line) && !occursin(r"^\s*\d{4}", line)
                    break
                end
                continue
            end

            if occursin(r"^\s*\d{4}", line)
                clean_line = replace(line, r"[\r]" => "")
                push!(lines, clean_line)
            end
        end
    end

    if !found_annual
        error("Annual Factors section not found in file")
    end

    lines_buffer = IOBuffer(join(lines, "\n"))
    return CSV.File(lines_buffer, header=false, delim=",", ntasks=1, types=types) |> DataFrame |>
           df -> rename!(df, col_names)
end
# --------------------------------------------------------------------------------------------------


# --------------------------------------------------------------------------------------------------
function _parse_ff_monthly(zip_file; types=nothing,
    col_names=[:datem, :mktrf, :smb, :hml, :rf])

    # Read all lines from the zip file entry
    file_lines = split(String(read(zip_file)), '\n')

    # Find the first data line (starts with digits, like "192607")
    skipto = 1
    for (i, line) in enumerate(file_lines)
        if occursin(r"^\s*\d{6}", line)
            skipto = i
            break
        end
    end

    # Collect data lines until we hit "Annual Factors"
    data_lines = String[]

    for i in skipto:length(file_lines)
        line = file_lines[i]

        # Stop when we hit Annual Factors section
        if occursin(r"Annual Factors", line)
            break
        end

        # Skip empty lines
        if occursin(r"^\s*$", line)
            continue
        end

        # Add non-empty data lines
        push!(data_lines, line)
    end

    # Create IOBuffer with header + data
    buffer = IOBuffer(join(data_lines, "\n"))

    return CSV.File(buffer, header=false, delim=",", ntasks=1, types=types) |> DataFrame |>
           df -> rename!(df, col_names)

end
# --------------------------------------------------------------------------------------------------
