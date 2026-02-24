###############################################################################
# Download and prepare data for `AR_shd_2010` analysis
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
cli_process_start("Downloading files for {.pkg AR_shd_2010}")

path_data <- download_redistricting_file("AR", "data-raw/AR", year = 2010)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path <- "data-out/AR_2010/shp_vtd.rds"
perim_path <- "data-out/AR_2010/perim.rds"
dir.create(here("data-out/AR_2010"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {
    cli_process_start("Preparing {.strong AR} shapefile")
    # read in redistricting data
    ar_shp <- read_csv(here(path_data)) |>
        join_vtd_shapefile(year = 2010) |>
        st_transform(EPSG$AR) |>
        rename_with(function(x) gsub("[0-9.]", "", x), starts_with("GEOID"))

    # add municipalities
    d_muni <- make_from_baf("AR", "INCPLACE_CDP", "VTD", year = 2010) |>
        mutate(GEOID = paste0(censable::match_fips("AR"), vtd)) |>
        select(-vtd)
    ar_shp <- left_join(ar_shp, d_muni, by = "GEOID") |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, .after = county)

    # add the enacted plan via geo_match with SLDL shapefile (post-2010 plans from TIGER 2013)
    sldl_shp <- st_read(here("data-raw/AR/sldl_2010/tl_2013_05_sldl.shp"), quiet = TRUE) |>
        st_transform(st_crs(ar_shp))
    ar_shp <- ar_shp |>
        mutate(shd_2010 = as.integer(sldl_shp$SLDLST)[
            geo_match(ar_shp, sldl_shp, method = "area")])

    # fix labeling
    ar_shp$state <- "AR"

    # eliminate empty shapes
    ar_shp <- ar_shp |> filter(!st_is_empty(geometry))

    # Create perimeters
    redistmetrics::prep_perims(shp = ar_shp,
        perim_path = here(perim_path)) |>
        invisible()

    # simplify geometry
    if (requireNamespace("rmapshaper", quietly = TRUE)) {
        ar_shp <- rmapshaper::ms_simplify(ar_shp, keep = 0.05,
            keep_shapes = TRUE) |>
            suppressWarnings()
    }

    # create adjacency graph
    ar_shp$adj <- redist.adjacency(ar_shp)

    # connect islands / disconnected precincts
    ar_shp$adj <- ar_shp$adj |>
        add_edge(suggest_neighbors(ar_shp, ar_shp$adj)$x,
                 suggest_neighbors(ar_shp, ar_shp$adj)$y)

    ar_shp <- ar_shp |>
        fix_geo_assignment(muni)

    # fill any remaining NA enacted values using adjacency (prevents extra district in redist_map)
    ar_shp <- fill_na_enacted(ar_shp, shd_2010)

    write_rds(ar_shp, here(shp_path), compress = "gz")
    cli_process_done()
} else {
    ar_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {.strong AR} shapefile")
}
