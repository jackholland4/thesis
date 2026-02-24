###############################################################################
# Download and prepare data for `LA_shd_2010` analysis
###############################################################################

suppressMessages({
    library(dplyr)
    library(readr)
    library(sf)
    library(redist)
    library(geomander)
    library(cli)
    library(here)
    devtools::load_all() # load utilities
})

# Download necessary files for analysis -----
cli_process_start("Downloading files for {.pkg LA_shd_2010}")

path_data <- download_redistricting_file("LA", "data-raw/LA", year = 2010)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path <- "data-out/LA_2010/shp_vtd.rds"
perim_path <- "data-out/LA_2010/perim.rds"
dir.create(here("data-out/LA_2010"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {
    cli_process_start("Preparing {.strong LA} shapefile")
    # read in redistricting data
    la_shp <- read_csv(here(path_data)) |>
        join_vtd_shapefile(year = 2010) |>
        st_transform(EPSG$LA) |>
        rename_with(function(x) gsub("[0-9.]", "", x), starts_with("GEOID"))

    # add municipalities
    d_muni <- make_from_baf("LA", "INCPLACE_CDP", "VTD", year = 2010) |>
        mutate(GEOID = paste0(censable::match_fips("LA"), vtd)) |>
        select(-vtd)
    la_shp <- left_join(la_shp, d_muni, by = "GEOID") |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, .after = county)

    # add the enacted plan via geo_match with SLDL shapefile (post-2010 plans from TIGER 2013)
    sldl_shp <- st_read(here("data-raw/LA/sldl_2010/tl_2013_22_sldl.shp"), quiet = TRUE) |>
        st_transform(st_crs(la_shp))
    la_shp <- la_shp |>
        mutate(shd_2010 = as.integer(sldl_shp$SLDLST)[
            geo_match(la_shp, sldl_shp, method = "area")])

    # fix labeling
    la_shp$state <- "LA"

    # eliminate empty shapes
    la_shp <- la_shp |> filter(!st_is_empty(geometry))

    # Create perimeters
    redistmetrics::prep_perims(shp = la_shp,
        perim_path = here(perim_path)) |>
        invisible()

    # simplify geometry
    if (requireNamespace("rmapshaper", quietly = TRUE)) {
        la_shp <- rmapshaper::ms_simplify(la_shp, keep = 0.05,
            keep_shapes = TRUE) |>
            suppressWarnings()
    }

    # create adjacency graph
    la_shp$adj <- redist.adjacency(la_shp)

    # connect islands / disconnected precincts
    la_shp$adj <- la_shp$adj |>
        add_edge(suggest_neighbors(la_shp, la_shp$adj)$x,
                 suggest_neighbors(la_shp, la_shp$adj)$y)

    la_shp <- la_shp |>
        fix_geo_assignment(muni)

    # fill any remaining NA enacted values using adjacency (prevents extra district in redist_map)
    la_shp <- fill_na_enacted(la_shp, shd_2010)

    write_rds(la_shp, here(shp_path), compress = "gz")
    cli_process_done()
} else {
    la_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {.strong LA} shapefile")
}
