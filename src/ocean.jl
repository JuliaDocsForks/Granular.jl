"Returns empty ocean type for initialization purposes."
function createEmptyOcean()
    return Ocean("",
                 zeros(1),
                 zeros(1),
                 zeros(1),
                 zeros(1),
                 zeros(1),
                 zeros(1),
                 zeros(1),
                 zeros(1,1,1,1),
                 zeros(1,1,1,1),
                 zeros(1,1,1,1),
                 zeros(1,1,1,1))
end

"""
Read NetCDF file generated by MOM6 (e.g. `prog__####_###.nc`) from disk and 
return as `Ocean` data structure.
"""
function readOceanNetCDF(filename::String)

    if !isfile(filename)
        error("$(filename) could not be opened")
    end

    ocean = Ocean(filename,
                  NetCDF.ncread(filename, "Time"),

                  NetCDF.ncread(filename, "xq"),
                  NetCDF.ncread(filename, "yq"),
                  NetCDF.ncread(filename, "xh"),
                  NetCDF.ncread(filename, "yh"),
                  NetCDF.ncread(filename, "zl"),
                  NetCDF.ncread(filename, "zi"),

                  NetCDF.ncread(filename, "u"),
                  NetCDF.ncread(filename, "v"),
                  NetCDF.ncread(filename, "h"),
                  NetCDF.ncread(filename, "e"))
    return ocean
end