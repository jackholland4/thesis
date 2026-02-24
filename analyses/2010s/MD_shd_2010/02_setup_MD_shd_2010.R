###############################################################################
# Set up redistricting simulation for `MD_shd_2010`
###############################################################################
cli_process_start("Creating {.cls redist_map} object for {.pkg MD_shd_2010}")

map_shd <- redist_map(md_shp, pop_tol = 0.05,
    existing_plan = shd_2010, adj = md_shp$adj)

# make pseudo counties with default settings
map_shd <- map_shd |>
    mutate(pseudo_county = pick_county_muni(map_shd, counties = county, munis = muni,
        pop_muni = get_target(map_shd)))

# Add an analysis name attribute
attr(map_shd, "analysis_name") <- "MD_SHD_2010"

# Output the redist_map object
write_rds(map_shd, "data-out/MD_2010/MD_shd_2010_map.rds", compress = "xz")
cli_process_done()
