###############################################################################
# Download and prepare data for `PA_shd_2010` analysis
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
cli_process_start("Downloading files for {.pkg PA_shd_2010}")

path_data <- download_redistricting_file("PA", "data-raw/PA", year = 2010)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path <- "data-out/PA_2010/shp_vtd.rds"
perim_path <- "data-out/PA_2010/perim.rds"
dir.create(here("data-out/PA_2010"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {
    cli_process_start("Preparing {.strong PA} shapefile")
    # read in redistricting data
    pa_shp <- read_csv(here(path_data)) |>
        join_vtd_shapefile(year = 2010) |>
        st_transform(EPSG$PA) |>
        rename_with(function(x) gsub("[0-9.]", "", x), starts_with("GEOID"))

    # add municipalities
    d_muni <- make_from_baf("PA", "INCPLACE_CDP", "VTD", year = 2010) |>
        mutate(GEOID = paste0(censable::match_fips("PA"), vtd)) |>
        select(-vtd)
    pa_shp <- left_join(pa_shp, d_muni, by = "GEOID") |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, .after = county)

    # add the enacted plan via geo_match with SLDL shapefile (post-2010 plans from TIGER 2013)
    sldl_shp <- st_read(here("data-raw/PA/sldl_2010/tl_2013_42_sldl.shp"), quiet = TRUE) |>
        st_transform(st_crs(pa_shp))
    pa_shp <- pa_shp |>
        mutate(shd_2010 = as.integer(sldl_shp$SLDLST)[
            geo_match(pa_shp, sldl_shp, method = "area")])

    # fix labeling
    pa_shp$state <- "PA"

    # eliminate empty shapes
    pa_shp <- pa_shp |> filter(!st_is_empty(geometry))

    # Create perimeters
    redistmetrics::prep_perims(shp = pa_shp,
        perim_path = here(perim_path)) |>
        invisible()

    # simplify geometry
    if (requireNamespace("rmapshaper", quietly = TRUE)) {
        pa_shp <- rmapshaper::ms_simplify(pa_shp, keep = 0.05,
            keep_shapes = TRUE) |>
            suppressWarnings()
    }

    # create adjacency graph
    pa_shp$adj <- redist.adjacency(pa_shp)

    # connect islands / disconnected precincts
    pa_shp$adj <- pa_shp$adj |>
        add_edge(suggest_neighbors(pa_shp, pa_shp$adj)$x,
                 suggest_neighbors(pa_shp, pa_shp$adj)$y)

    pa_shp <- pa_shp |>
        fix_geo_assignment(muni)

    # fill any remaining NA enacted values using adjacency (prevents extra district in redist_map)
    pa_shp <- fill_na_enacted(pa_shp, shd_2010)

    write_rds(pa_shp, here(shp_path), compress = "gz")
    cli_process_done()
} else {
    pa_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {.strong PA} shapefile")
}
