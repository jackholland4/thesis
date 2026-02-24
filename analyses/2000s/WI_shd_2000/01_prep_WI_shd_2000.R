###############################################################################
# Download and prepare data for `WI_shd_2000` analysis
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
cli_process_start("Downloading files for {.pkg WI_shd_2000}")

path_data <- download_redistricting_file("WI", "data-raw/WI", year = 2000)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path <- "data-out/WI_2000/shp_vtd.rds"
perim_path <- "data-out/WI_2000/perim.rds"
dir.create(here("data-out/WI_2000"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {
    cli_process_start("Preparing {.strong WI} shapefile")
    # read in redistricting data
    wi_shp <- read_csv(here(path_data), col_types = cols(GEOID = "c")) |>
        join_vtd_shapefile(year = 2000) |>
        st_transform(EPSG$WI)

    wi_shp <- wi_shp |>
        rename(muni = place) |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, .after = county)

    # add the enacted plan via geo_match with SLDL shapefile (post-2000 plans from TIGER 2010)
    sldl_shp <- st_read(here("data-raw/WI/sldl_2000/tl_2010_55_sldl10.shp"), quiet = TRUE) |>
        st_transform(st_crs(wi_shp))
    wi_shp <- wi_shp |>
        mutate(shd_2000 = as.integer(sldl_shp$SLDLST10)[
            geo_match(wi_shp, sldl_shp, method = "area")])

    # fix labeling
    wi_shp$state <- "WI"

    # eliminate empty shapes
    wi_shp <- wi_shp |> filter(!st_is_empty(geometry))

    # Create perimeters
    redistmetrics::prep_perims(shp = wi_shp,
        perim_path = here(perim_path)) |>
        invisible()

    # simplify geometry
    if (requireNamespace("rmapshaper", quietly = TRUE)) {
        wi_shp <- rmapshaper::ms_simplify(wi_shp, keep = 0.05,
            keep_shapes = TRUE) |>
            suppressWarnings()
    }

    # create adjacency graph
    wi_shp$adj <- redist.adjacency(wi_shp)

    # connect islands / disconnected precincts
    wi_shp$adj <- wi_shp$adj |>
        add_edge(suggest_neighbors(wi_shp, wi_shp$adj)$x,
                 suggest_neighbors(wi_shp, wi_shp$adj)$y)

    # fill any remaining NA enacted values using adjacency (prevents extra district in redist_map)
    wi_shp <- fill_na_enacted(wi_shp, shd_2000)

    write_rds(wi_shp, here(shp_path), compress = "gz")
    cli_process_done()
} else {
    wi_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {.strong WI} shapefile")
}
