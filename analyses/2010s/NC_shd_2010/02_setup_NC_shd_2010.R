###############################################################################
# Set up redistricting simulation for `NC_shd_2010`
###############################################################################
cli_process_start("Creating {.cls redist_map} object for {.pkg NC_shd_2010}")

map_shd <- redist_map(nc_shp, pop_tol = 0.05,
    existing_plan = shd_2010, adj = nc_shp$adj)

# make pseudo counties with default settings
map_shd <- map_shd |>
    mutate(pseudo_county = pick_county_muni(map_shd, counties = county, munis = muni,
        pop_muni = get_target(map_shd)))

# Add an analysis name attribute
attr(map_shd, "analysis_name") <- "NC_SHD_2010"

# Output the redist_map object
write_rds(map_shd, "data-out/NC_2010/NC_shd_2010_map.rds", compress = "xz")
cli_process_done()
