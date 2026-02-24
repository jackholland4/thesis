###############################################################################
# Download and prepare data for `MO_shd_2020` analysis
###############################################################################

suppressMessages({
    library(dplyr)
    library(readr)
    library(sf)
    library(redist)
    library(geomander)
    library(cli)
    library(here)
    library(tinytiger)
    devtools::load_all() # load utilities
})

# Download necessary files for analysis -----
cli_process_start("Downloading files for {.pkg MO_shd_2020}")

path_data <- download_redistricting_file("MO", "data-raw/MO", year = 2020)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path <- "data-out/MO_2020/shp_vtd.rds"
perim_path <- "data-out/MO_2020/perim.rds"
dir.create(here("data-out/MO_2020"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {
    cli_process_start("Preparing {.strong MO} shapefile")
    # read in redistricting data
    mo_shp <- read_csv(here(path_data), col_types = cols(GEOID20 = "c")) |>
        join_vtd_shapefile(year = 2020) |>
        st_transform(EPSG$MO) |>
        rename_with(function(x) gsub("[0-9.]", "", x), starts_with("GEOID"))

    # add municipalities
    d_muni <- make_from_baf("MO", "INCPLACE_CDP", "VTD", year = 2020) |>
        mutate(GEOID = paste0(censable::match_fips("MO"), vtd)) |>
        select(-vtd)
    mo_shp <- left_join(mo_shp, d_muni, by = "GEOID") |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, .after = county)

    # add the enacted plan via geo_match with SLDL shapefile
    sldl_shp <- st_read(here("data-raw/MO/sldl_2020/tl_2022_29_sldl.shp"), quiet = TRUE) |>
        st_transform(st_crs(mo_shp))
    mo_shp <- mo_shp |>
        mutate(shd_2020 = as.integer(sldl_shp$SLDLST)[
            geo_match(mo_shp, sldl_shp, method = "area")])

    # fix labeling
    mo_shp$state <- "MO"

    # eliminate empty shapes
    mo_shp <- mo_shp |> filter(!st_is_empty(geometry))

    # Create perimeters
    redistmetrics::prep_perims(shp = mo_shp,
        perim_path = here(perim_path)) |>
        invisible()

    # simplify geometry
    if (requireNamespace("rmapshaper", quietly = TRUE)) {
        mo_shp <- rmapshaper::ms_simplify(mo_shp, keep = 0.05,
            keep_shapes = TRUE) |>
            suppressWarnings()
    }

    # create adjacency graph
    mo_shp$adj <- redist.adjacency(mo_shp)

    # connect islands / disconnected precincts
    mo_shp$adj <- mo_shp$adj |>
        add_edge(suggest_neighbors(mo_shp, mo_shp$adj)$x,
                 suggest_neighbors(mo_shp, mo_shp$adj)$y)

    mo_shp <- mo_shp |>
        fix_geo_assignment(muni)

    # fill any remaining NA enacted values using adjacency (prevents extra district in redist_map)
    mo_shp <- fill_na_enacted(mo_shp, shd_2020)

    write_rds(mo_shp, here(shp_path), compress = "gz")
    cli_process_done()
} else {
    mo_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {.strong MO} shapefile")
}
