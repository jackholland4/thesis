###############################################################################
# Download and prepare data for `GA_shd_2020` analysis
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
cli_process_start("Downloading files for {.pkg GA_shd_2020}")

path_data <- download_redistricting_file("GA", "data-raw/GA", year = 2020)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path <- "data-out/GA_2020/shp_vtd.rds"
perim_path <- "data-out/GA_2020/perim.rds"
dir.create(here("data-out/GA_2020"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {
    cli_process_start("Preparing {.strong GA} shapefile")
    # read in redistricting data
    ga_shp <- read_csv(here(path_data), col_types = cols(GEOID20 = "c")) |>
        join_vtd_shapefile(year = 2020) |>
        st_transform(EPSG$GA) |>
        rename_with(function(x) gsub("[0-9.]", "", x), starts_with("GEOID"))

    # add municipalities
    d_muni <- make_from_baf("GA", "INCPLACE_CDP", "VTD", year = 2020) |>
        mutate(GEOID = paste0(censable::match_fips("GA"), vtd)) |>
        select(-vtd)
    ga_shp <- left_join(ga_shp, d_muni, by = "GEOID") |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, .after = county)

    # add the enacted plan via geo_match with SLDL shapefile
    sldl_shp <- st_read(here("data-raw/GA/sldl_2020/tl_2022_13_sldl.shp"), quiet = TRUE) |>
        st_transform(st_crs(ga_shp))
    ga_shp <- ga_shp |>
        mutate(shd_2020 = as.integer(sldl_shp$SLDLST)[
            geo_match(ga_shp, sldl_shp, method = "area")])

    # fix labeling
    ga_shp$state <- "GA"

    # eliminate empty shapes
    ga_shp <- ga_shp |> filter(!st_is_empty(geometry))

    # Create perimeters
    redistmetrics::prep_perims(shp = ga_shp,
        perim_path = here(perim_path)) |>
        invisible()

    # simplify geometry
    if (requireNamespace("rmapshaper", quietly = TRUE)) {
        ga_shp <- rmapshaper::ms_simplify(ga_shp, keep = 0.05,
            keep_shapes = TRUE) |>
            suppressWarnings()
    }

    # create adjacency graph
    ga_shp$adj <- redist.adjacency(ga_shp)

    # connect islands / disconnected precincts
    ga_shp$adj <- ga_shp$adj |>
        add_edge(suggest_neighbors(ga_shp, ga_shp$adj)$x,
                 suggest_neighbors(ga_shp, ga_shp$adj)$y)

    ga_shp <- ga_shp |>
        fix_geo_assignment(muni)

    # fill any remaining NA enacted values using adjacency (prevents extra district in redist_map)
    ga_shp <- fill_na_enacted(ga_shp, shd_2020)

    write_rds(ga_shp, here(shp_path), compress = "gz")
    cli_process_done()
} else {
    ga_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {.strong GA} shapefile")
}
