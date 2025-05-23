# --------------------------------------------------------------------------------------------------

# ImportFamaFrench.jl

# Collection of functions that import
#  financial data from Ken French's website into julia
# --------------------------------------------------------------------------------------------------



# --------------------------------------------------------------------------------------------------
# List of exported functions
# export import_FF3             # read monthly FF3
# --------------------------------------------------------------------------------------------------



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

    ff_col_classes = [String7, Float64, Float64, Float64, Float64];
    url_FF_mth_yr = "https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/ftp/F-F_Research_Data_Factors_CSV.zip"
    url_FF_daily  = "https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/ftp/F-F_Research_Data_Factors_daily_CSV.zip"

    # ----------------------------------------------------------------------------------------------
    if frequency==:annual

        http_response = Downloads.download(url_FF_mth_yr);
        z = ZipFile.Reader(http_response) ;
        a_file_in_zip = filter(x -> match(r".*csv", lowercase(x.name)) != nothing, z.files)[1]
        df_FF3 = copy(_parse_ff_annual(a_file_in_zip, types=ff_col_classes))
        close(z)
        return df_FF3

    # ----------------------------------------------------------------------------------------------
    elseif frequency==:monthly

        http_response = Downloads.download(url_FF_mth_yr);
        z = ZipFile.Reader(http_response) ;
        a_file_in_zip = filter(x -> match(r".*csv", lowercase(x.name)) != nothing, z.files)[1]
        df_FF3 = copy(_parse_ff_monthly(a_file_in_zip, types=ff_col_classes))
        close(z)

        transform!(df_FF3, :datem => ByRow(x -> MonthlyDate(x, "yyyymm")) => :datem)
        return df_FF3


    # ----------------------------------------------------------------------------------------------
    elseif frequency==:daily
        
        http_response = Downloads.download(url_FF_daily);
        z = ZipFile.Reader(http_response) ;
        a_file_in_zip = filter(x -> match(r".*csv", lowercase(x.name)) != nothing, z.files)[1]
        df_FF3 = copy(CSV.File(a_file_in_zip, header=4, footerskip=1) |> DataFrame);
        close(z)
        rename!(df_FF3, [:date, :mktrf, :smb, :hml, :rf]);
        df_FF3 = @p df_FF3 |> filter(.!ismissing.(_.date) && .!ismissing.(_.mktrf))
        transform!(df_FF3, :date => ByRow(x -> Date(string(x), "yyyymmdd") ) => :date)
        return df_FF3

    # ----------------------------------------------------------------------------------------------
    else
        error("Frequency $frequency not known. Options are :daily, :monthly, or :annual")
    end

end
# --------------------------------------------------------------------------------------------------


# --------------------------------------------------------------------------------------------------
function _parse_ff_annual(zip_file; types=nothing)

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
                if !occursin(r"^\s*$", line) && !occursin(r"^\d{4}", line)
                    break
                end
                continue
            end
            
            if occursin(r"^\d{4}", line)
                push!(lines, line)
            end
        end
    end
    
    if !found_annual
        error("Annual Factors section not found in file")
    end
    
    buffer = IOBuffer(join(lines, "\n"))
    return CSV.File(buffer, header=false, delim=",", ntasks=1, types=types) |> DataFrame |>
           df -> rename!(df, [:datey, :mktrf, :smb, :hml, :rf])
end
# --------------------------------------------------------------------------------------------------


# --------------------------------------------------------------------------------------------------
function _parse_ff_monthly(zip_file; types=nothing)
    

    # Read all lines from the zip file entry
    file_lines = split(String(read(zip_file)), '\n')
    skipto = 5

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
           df -> rename!(df, [:datem, :mktrf, :smb, :hml, :rf])

end
# --------------------------------------------------------------------------------------------------
