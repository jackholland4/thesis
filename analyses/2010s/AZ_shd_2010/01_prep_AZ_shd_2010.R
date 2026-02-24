###############################################################################
# Download and prepare data for `AZ_shd_2010` analysis
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
cli_process_start("Downloading files for {.pkg AZ_shd_2010}")

path_data <- download_redistricting_file("AZ", "data-raw/AZ", year = 2010)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path <- "data-out/AZ_2010/shp_vtd.rds"
perim_path <- "data-out/AZ_2010/perim.rds"
dir.create(here("data-out/AZ_2010"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {
    cli_process_start("Preparing {.strong AZ} shapefile")
    # read in redistricting data
    az_shp <- read_csv(here(path_data)) |>
        join_vtd_shapefile(year = 2010) |>
        st_transform(EPSG$AZ) |>
        rename_with(function(x) gsub("[0-9.]", "", x), starts_with("GEOID"))

    # add municipalities
    d_muni <- make_from_baf("AZ", "INCPLACE_CDP", "VTD", year = 2010) |>
        mutate(GEOID = paste0(censable::match_fips("AZ"), vtd)) |>
        select(-vtd)
    az_shp <- left_join(az_shp, d_muni, by = "GEOID") |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, .after = county)

    # add the enacted plan via geo_match with SLDL shapefile (post-2010 plans from TIGER 2013)
    sldl_shp <- st_read(here("data-raw/AZ/sldl_2010/tl_2013_04_sldl.shp"), quiet = TRUE) |>
        st_transform(st_crs(az_shp))
    az_shp <- az_shp |>
        mutate(shd_2010 = as.integer(sldl_shp$SLDLST)[
            geo_match(az_shp, sldl_shp, method = "area")])

    # fix labeling
    az_shp$state <- "AZ"

    # eliminate empty shapes
    az_shp <- az_shp |> filter(!st_is_empty(geometry))

    # Create perimeters
    redistmetrics::prep_perims(shp = az_shp,
        perim_path = here(perim_path)) |>
        invisible()

    # simplify geometry
    if (requireNamespace("rmapshaper", quietly = TRUE)) {
        az_shp <- rmapshaper::ms_simplify(az_shp, keep = 0.05,
            keep_shapes = TRUE) |>
            suppressWarnings()
    }

    # create adjacency graph
    az_shp$adj <- redist.adjacency(az_shp)

    # connect islands / disconnected precincts
    az_shp$adj <- az_shp$adj |>
        add_edge(suggest_neighbors(az_shp, az_shp$adj)$x,
                 suggest_neighbors(az_shp, az_shp$adj)$y)

    az_shp <- az_shp |>
        fix_geo_assignment(muni)

    # fill any remaining NA enacted values using adjacency (prevents extra district in redist_map)
    az_shp <- fill_na_enacted(az_shp, shd_2010)

    write_rds(az_shp, here(shp_path), compress = "gz")
    cli_process_done()
} else {
    az_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {.strong AZ} shapefile")
}
