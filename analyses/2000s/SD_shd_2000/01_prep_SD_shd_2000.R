###############################################################################
# Download and prepare data for `SD_shd_2000` analysis
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
cli_process_start("Downloading files for {.pkg SD_shd_2000}")

path_data <- download_redistricting_file("SD", "data-raw/SD", year = 2000)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path <- "data-out/SD_2000/shp_vtd.rds"
perim_path <- "data-out/SD_2000/perim.rds"
dir.create(here("data-out/SD_2000"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {
    cli_process_start("Preparing {.strong SD} shapefile")
    # read in redistricting data
    sd_shp <- read_csv(here(path_data), col_types = cols(GEOID = "c")) |>
        join_vtd_shapefile(year = 2000) |>
        st_transform(EPSG$SD)

    sd_shp <- sd_shp |>
        rename(muni = place) |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, .after = county)

    # add the enacted plan via geo_match with SLDL shapefile (post-2000 plans from TIGER 2010)
    sldl_shp <- st_read(here("data-raw/SD/sldl_2000/tl_2010_46_sldl10.shp"), quiet = TRUE) |>
        st_transform(st_crs(sd_shp))
    sd_shp <- sd_shp |>
        mutate(shd_2000 = as.integer(sldl_shp$SLDLST10)[
            geo_match(sd_shp, sldl_shp, method = "area")])

    # fix labeling
    sd_shp$state <- "SD"

    # eliminate empty shapes
    sd_shp <- sd_shp |> filter(!st_is_empty(geometry))

    # Create perimeters
    redistmetrics::prep_perims(shp = sd_shp,
        perim_path = here(perim_path)) |>
        invisible()

    # simplify geometry
    if (requireNamespace("rmapshaper", quietly = TRUE)) {
        sd_shp <- rmapshaper::ms_simplify(sd_shp, keep = 0.05,
            keep_shapes = TRUE) |>
            suppressWarnings()
    }

    # create adjacency graph
    sd_shp$adj <- redist.adjacency(sd_shp)

    # connect islands / disconnected precincts
    sd_shp$adj <- sd_shp$adj |>
        add_edge(suggest_neighbors(sd_shp, sd_shp$adj)$x,
                 suggest_neighbors(sd_shp, sd_shp$adj)$y)

    # fill any remaining NA enacted values using adjacency (prevents extra district in redist_map)
    sd_shp <- fill_na_enacted(sd_shp, shd_2000)

    write_rds(sd_shp, here(shp_path), compress = "gz")
    cli_process_done()
} else {
    sd_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {.strong SD} shapefile")
}
