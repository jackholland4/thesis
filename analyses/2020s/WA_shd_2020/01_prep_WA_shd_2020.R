###############################################################################
# Download and prepare data for `WA_shd_2020` analysis
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
cli_process_start("Downloading files for {.pkg WA_shd_2020}")

path_data <- download_redistricting_file("WA", "data-raw/WA", year = 2020)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path <- "data-out/WA_2020/shp_vtd.rds"
perim_path <- "data-out/WA_2020/perim.rds"
dir.create(here("data-out/WA_2020"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {
    cli_process_start("Preparing {.strong WA} shapefile")
    # read in redistricting data
    wa_shp <- read_csv(here(path_data), col_types = cols(GEOID20 = "c")) |>
        join_vtd_shapefile(year = 2020) |>
        st_transform(EPSG$WA) |>
        rename_with(function(x) gsub("[0-9.]", "", x), starts_with("GEOID"))

    # add municipalities
    d_muni <- make_from_baf("WA", "INCPLACE_CDP", "VTD", year = 2020) |>
        mutate(GEOID = paste0(censable::match_fips("WA"), vtd)) |>
        select(-vtd)
    wa_shp <- left_join(wa_shp, d_muni, by = "GEOID") |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, .after = county)

    # add the enacted plan via geo_match with SLDL shapefile
    sldl_shp <- st_read(here("data-raw/WA/sldl_2020/tl_2022_53_sldl.shp"), quiet = TRUE) |>
        st_transform(st_crs(wa_shp))
    wa_shp <- wa_shp |>
        mutate(shd_2020 = as.integer(sldl_shp$SLDLST)[
            geo_match(wa_shp, sldl_shp, method = "area")])

    # fix labeling
    wa_shp$state <- "WA"

    # eliminate empty shapes
    wa_shp <- wa_shp |> filter(!st_is_empty(geometry))

    # Create perimeters
    redistmetrics::prep_perims(shp = wa_shp,
        perim_path = here(perim_path)) |>
        invisible()

    # simplify geometry
    if (requireNamespace("rmapshaper", quietly = TRUE)) {
        wa_shp <- rmapshaper::ms_simplify(wa_shp, keep = 0.05,
            keep_shapes = TRUE) |>
            suppressWarnings()
    }

    # create adjacency graph
    wa_shp$adj <- redist.adjacency(wa_shp)

    # connect islands / disconnected precincts
    wa_shp$adj <- wa_shp$adj |>
        add_edge(suggest_neighbors(wa_shp, wa_shp$adj)$x,
                 suggest_neighbors(wa_shp, wa_shp$adj)$y)

    wa_shp <- wa_shp |>
        fix_geo_assignment(muni)

    # fill any remaining NA enacted values using adjacency (prevents extra district in redist_map)
    wa_shp <- fill_na_enacted(wa_shp, shd_2020)

    write_rds(wa_shp, here(shp_path), compress = "gz")
    cli_process_done()
} else {
    wa_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {.strong WA} shapefile")
}
