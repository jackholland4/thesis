###############################################################################
# Download and prepare data for `WV_shd_2010` analysis
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
cli_process_start("Downloading files for {.pkg WV_shd_2010}")

path_data <- download_redistricting_file("WV", "data-raw/WV", year = 2010)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path <- "data-out/WV_2010/shp_vtd.rds"
perim_path <- "data-out/WV_2010/perim.rds"
dir.create(here("data-out/WV_2010"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {
    cli_process_start("Preparing {.strong WV} shapefile")
    # read in redistricting data
    wv_shp <- read_csv(here(path_data)) |>
        join_vtd_shapefile(year = 2010) |>
        st_transform(EPSG$WV) |>
        rename_with(function(x) gsub("[0-9.]", "", x), starts_with("GEOID"))

    # add municipalities
    d_muni <- make_from_baf("WV", "INCPLACE_CDP", "VTD", year = 2010) |>
        mutate(GEOID = paste0(censable::match_fips("WV"), vtd)) |>
        select(-vtd)
    wv_shp <- left_join(wv_shp, d_muni, by = "GEOID") |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, .after = county)

    # add the enacted plan via geo_match with SLDL shapefile (post-2010 plans from TIGER 2013)
    sldl_shp <- st_read(here("data-raw/WV/sldl_2010/tl_2013_54_sldl.shp"), quiet = TRUE) |>
        st_transform(st_crs(wv_shp))
    wv_shp <- wv_shp |>
        mutate(shd_2010 = as.integer(sldl_shp$SLDLST)[
            geo_match(wv_shp, sldl_shp, method = "area")])

    # fix labeling
    wv_shp$state <- "WV"

    # eliminate empty shapes
    wv_shp <- wv_shp |> filter(!st_is_empty(geometry))

    # Create perimeters
    redistmetrics::prep_perims(shp = wv_shp,
        perim_path = here(perim_path)) |>
        invisible()

    # simplify geometry
    if (requireNamespace("rmapshaper", quietly = TRUE)) {
        wv_shp <- rmapshaper::ms_simplify(wv_shp, keep = 0.05,
            keep_shapes = TRUE) |>
            suppressWarnings()
    }

    # create adjacency graph
    wv_shp$adj <- redist.adjacency(wv_shp)

    # connect islands / disconnected precincts
    wv_shp$adj <- wv_shp$adj |>
        add_edge(suggest_neighbors(wv_shp, wv_shp$adj)$x,
                 suggest_neighbors(wv_shp, wv_shp$adj)$y)

    wv_shp <- wv_shp |>
        fix_geo_assignment(muni)

    # fill any remaining NA enacted values using adjacency (prevents extra district in redist_map)
    wv_shp <- fill_na_enacted(wv_shp, shd_2010)

    write_rds(wv_shp, here(shp_path), compress = "gz")
    cli_process_done()
} else {
    wv_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {.strong WV} shapefile")
}
