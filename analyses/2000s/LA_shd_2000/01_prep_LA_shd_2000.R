###############################################################################
# Download and prepare data for `LA_shd_2000` analysis
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
cli_process_start("Downloading files for {.pkg LA_shd_2000}")

path_data <- download_redistricting_file("LA", "data-raw/LA", year = 2000)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path <- "data-out/LA_2000/shp_vtd.rds"
perim_path <- "data-out/LA_2000/perim.rds"
dir.create(here("data-out/LA_2000"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {
    cli_process_start("Preparing {.strong LA} shapefile")
    # read in redistricting data
    la_shp <- read_csv(here(path_data), col_types = cols(GEOID = "c")) |>
        join_vtd_shapefile(year = 2000) |>
        st_transform(EPSG$LA)

    la_shp <- la_shp |>
        rename(muni = place) |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, .after = county)

    # add the enacted plan via geo_match with SLDL shapefile (post-2000 plans from TIGER 2010)
    sldl_shp <- st_read(here("data-raw/LA/sldl_2000/tl_2010_22_sldl10.shp"), quiet = TRUE) |>
        st_transform(st_crs(la_shp))
    la_shp <- la_shp |>
        mutate(shd_2000 = as.integer(sldl_shp$SLDLST10)[
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

    # fill any remaining NA enacted values using adjacency (prevents extra district in redist_map)
    la_shp <- fill_na_enacted(la_shp, shd_2000)

    write_rds(la_shp, here(shp_path), compress = "gz")
    cli_process_done()
} else {
    la_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {.strong LA} shapefile")
}
