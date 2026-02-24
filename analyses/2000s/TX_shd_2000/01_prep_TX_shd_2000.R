###############################################################################
# Download and prepare data for `TX_shd_2000` analysis
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
cli_process_start("Downloading files for {.pkg TX_shd_2000}")

path_data <- download_redistricting_file("TX", "data-raw/TX", year = 2000)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path <- "data-out/TX_2000/shp_vtd.rds"
perim_path <- "data-out/TX_2000/perim.rds"
dir.create(here("data-out/TX_2000"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {
    cli_process_start("Preparing {.strong TX} shapefile")
    # read in redistricting data
    tx_shp <- read_csv(here(path_data), col_types = cols(GEOID = "c")) |>
        join_vtd_shapefile(year = 2000) |>
        st_transform(EPSG$TX)

    tx_shp <- tx_shp |>
        rename(muni = place) |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, .after = county)

    # add the enacted plan via geo_match with SLDL shapefile (post-2000 plans from TIGER 2010)
    sldl_shp <- st_read(here("data-raw/TX/sldl_2000/tl_2010_48_sldl10.shp"), quiet = TRUE) |>
        st_transform(st_crs(tx_shp))
    tx_shp <- tx_shp |>
        mutate(shd_2000 = as.integer(sldl_shp$SLDLST10)[
            geo_match(tx_shp, sldl_shp, method = "area")])

    # fix labeling
    tx_shp$state <- "TX"

    # eliminate empty shapes
    tx_shp <- tx_shp |> filter(!st_is_empty(geometry))

    # Create perimeters
    redistmetrics::prep_perims(shp = tx_shp,
        perim_path = here(perim_path)) |>
        invisible()

    # simplify geometry
    if (requireNamespace("rmapshaper", quietly = TRUE)) {
        tx_shp <- rmapshaper::ms_simplify(tx_shp, keep = 0.05,
            keep_shapes = TRUE) |>
            suppressWarnings()
    }

    # create adjacency graph
    tx_shp$adj <- redist.adjacency(tx_shp)

    # connect islands / disconnected precincts
    tx_shp$adj <- tx_shp$adj |>
        add_edge(suggest_neighbors(tx_shp, tx_shp$adj)$x,
                 suggest_neighbors(tx_shp, tx_shp$adj)$y)

    # fill any remaining NA enacted values using adjacency (prevents extra district in redist_map)
    tx_shp <- fill_na_enacted(tx_shp, shd_2000)

    write_rds(tx_shp, here(shp_path), compress = "gz")
    cli_process_done()
} else {
    tx_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {.strong TX} shapefile")
}
