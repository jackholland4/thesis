###############################################################################
# Set up redistricting simulation for `KS_shd_2020`
###############################################################################
cli_process_start("Creating {.cls redist_map} object for {.pkg KS_shd_2020}")

map_shd <- redist_map(ks_shp, pop_tol = 0.05,
    existing_plan = shd_2020, adj = ks_shp$adj)

# make pseudo counties with default settings
map_shd <- map_shd |>
    mutate(pseudo_county = pick_county_muni(map_shd, counties = county, munis = muni,
        pop_muni = get_target(map_shd)))

# Add an analysis name attribute
attr(map_shd, "analysis_name") <- "KS_SHD_2020"

# Output the redist_map object
write_rds(map_shd, "data-out/KS_2020/KS_shd_2020_map.rds", compress = "xz")
cli_process_done()
