###############################################################################
# Download and prepare data for `IL_shd_2000` analysis
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
cli_process_start("Downloading files for {.pkg IL_shd_2000}")

path_data <- download_redistricting_file("IL", "data-raw/IL", year = 2000)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path <- "data-out/IL_2000/shp_vtd.rds"
perim_path <- "data-out/IL_2000/perim.rds"
dir.create(here("data-out/IL_2000"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {
    cli_process_start("Preparing {.strong IL} shapefile")
    # read in redistricting data
    il_shp <- read_csv(here(path_data), col_types = cols(GEOID = "c")) |>
        join_vtd_shapefile(year = 2000) |>
        st_transform(EPSG$IL)

    il_shp <- il_shp |>
        rename(muni = place) |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, .after = county)

    # add the enacted plan via geo_match with SLDL shapefile (post-2000 plans from TIGER 2010)
    sldl_shp <- st_read(here("data-raw/IL/sldl_2000/tl_2010_17_sldl10.shp"), quiet = TRUE) |>
        st_transform(st_crs(il_shp))
    il_shp <- il_shp |>
        mutate(shd_2000 = as.integer(sldl_shp$SLDLST10)[
            geo_match(il_shp, sldl_shp, method = "area")])

    # fix labeling
    il_shp$state <- "IL"

    # eliminate empty shapes
    il_shp <- il_shp |> filter(!st_is_empty(geometry))

    # Create perimeters
    redistmetrics::prep_perims(shp = il_shp,
        perim_path = here(perim_path)) |>
        invisible()

    # simplify geometry
    if (requireNamespace("rmapshaper", quietly = TRUE)) {
        il_shp <- rmapshaper::ms_simplify(il_shp, keep = 0.05,
            keep_shapes = TRUE) |>
            suppressWarnings()
    }

    # create adjacency graph
    il_shp$adj <- redist.adjacency(il_shp)

    # connect islands / disconnected precincts
    il_shp$adj <- il_shp$adj |>
        add_edge(suggest_neighbors(il_shp, il_shp$adj)$x,
                 suggest_neighbors(il_shp, il_shp$adj)$y)

    # fill any remaining NA enacted values using adjacency (prevents extra district in redist_map)
    il_shp <- fill_na_enacted(il_shp, shd_2000)

    write_rds(il_shp, here(shp_path), compress = "gz")
    cli_process_done()
} else {
    il_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {.strong IL} shapefile")
}
