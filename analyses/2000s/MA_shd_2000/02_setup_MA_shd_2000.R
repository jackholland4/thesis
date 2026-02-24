###############################################################################
# Set up redistricting simulation for `MA_shd_2000`
###############################################################################
cli_process_start("Creating {.cls redist_map} object for {.pkg MA_shd_2000}")

map_shd <- redist_map(ma_shp, pop_tol = 0.05,
    existing_plan = shd_2000, adj = ma_shp$adj)

# make pseudo counties with default settings
map_shd <- map_shd |>
    mutate(pseudo_county = pick_county_muni(map_shd, counties = county, munis = muni,
        pop_muni = get_target(map_shd)))

# Add an analysis name attribute
attr(map_shd, "analysis_name") <- "MA_SHD_2000"

# Output the redist_map object
write_rds(map_shd, "data-out/MA_2000/MA_shd_2000_map.rds", compress = "xz")
cli_process_done()
