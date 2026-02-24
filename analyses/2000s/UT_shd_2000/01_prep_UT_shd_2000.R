###############################################################################
# Download and prepare data for `UT_shd_2000` analysis
###############################################################################

suppressMessages({
    library(dplyr)
    library(readr)
    library(sf)
    library(redist)
    library(geomander)
    library(baf)
    library(cli)
    library(here)
    devtools::load_all() # load utilities
})

# Download necessary files for analysis -----
cli_process_start("Downloading files for {.pkg UT_shd_2000}")

path_data <- download_redistricting_file("UT", "data-raw/UT", year = 2000)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path <- "data-out/UT_2000/shp_vtd.rds"
perim_path <- "data-out/UT_2000/perim.rds"
dir.create(here("data-out/UT_2000"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {
    cli_process_start("Preparing {.strong UT} shapefile")
    # read in redistricting data
    ut_shp <- read_csv(here(path_data), col_types = cols(GEOID = "c")) |>
        join_vtd_shapefile(year = 2000) |>
        st_transform(EPSG$UT)

    ut_shp <- ut_shp |>
        rename(muni = place) |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, .after = county)

    # add the enacted plan via geo_match with SLDL shapefile (post-2000 plans from TIGER 2010)
    sldl_shp <- st_read(here("data-raw/UT/sldl_2000/tl_2010_49_sldl10.shp"), quiet = TRUE) |>
        st_transform(st_crs(ut_shp))
    ut_shp <- ut_shp |>
        mutate(shd_2000 = as.integer(sldl_shp$SLDLST10)[
            geo_match(ut_shp, sldl_shp, method = "area")])

    # fix labeling
    ut_shp$state <- "UT"

    # eliminate empty shapes
    ut_shp <- ut_shp |> filter(!st_is_empty(geometry))

    # Create perimeters
    redistmetrics::prep_perims(shp = ut_shp,
        perim_path = here(perim_path)) |>
        invisible()

    # simplify geometry
    if (requireNamespace("rmapshaper", quietly = TRUE)) {
        ut_shp <- rmapshaper::ms_simplify(ut_shp, keep = 0.05,
            keep_shapes = TRUE) |>
            suppressWarnings()
    }

    # create adjacency graph
    ut_shp$adj <- redist.adjacency(ut_shp)

    # connect islands / disconnected precincts
    ut_shp$adj <- ut_shp$adj |>
        add_edge(suggest_neighbors(ut_shp, ut_shp$adj)$x,
                 suggest_neighbors(ut_shp, ut_shp$adj)$y)

    # fill any remaining NA enacted values using adjacency (prevents extra district in redist_map)
    ut_shp <- fill_na_enacted(ut_shp, shd_2000)

    write_rds(ut_shp, here(shp_path), compress = "gz")
    cli_process_done()
} else {
    ut_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {.strong UT} shapefile")
}
