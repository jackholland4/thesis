###############################################################################
# Set up redistricting simulation for `FL_shd_2000`
###############################################################################
cli_process_start("Creating {.cls redist_map} object for {.pkg FL_shd_2000}")

map_shd <- redist_map(fl_shp, pop_tol = 0.05,
    existing_plan = shd_2000, adj = fl_shp$adj)

# make pseudo counties with default settings
map_shd <- map_shd |>
    mutate(pseudo_county = pick_county_muni(map_shd, counties = county, munis = muni,
        pop_muni = get_target(map_shd)))

# Add an analysis name attribute
attr(map_shd, "analysis_name") <- "FL_SHD_2000"

# Output the redist_map object
write_rds(map_shd, "data-out/FL_2000/FL_shd_2000_map.rds", compress = "xz")
cli_process_done()
