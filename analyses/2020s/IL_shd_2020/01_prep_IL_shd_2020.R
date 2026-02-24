###############################################################################
# Download and prepare data for `IL_shd_2020` analysis
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
cli_process_start("Downloading files for {.pkg IL_shd_2020}")

path_data <- download_redistricting_file("IL", "data-raw/IL", year = 2020)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path <- "data-out/IL_2020/shp_vtd.rds"
perim_path <- "data-out/IL_2020/perim.rds"
dir.create(here("data-out/IL_2020"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {
    cli_process_start("Preparing {.strong IL} shapefile")
    # read in redistricting data
    il_shp <- read_csv(here(path_data), col_types = cols(GEOID20 = "c")) |>
        join_vtd_shapefile(year = 2020) |>
        st_transform(EPSG$IL) |>
        rename_with(function(x) gsub("[0-9.]", "", x), starts_with("GEOID"))

    # add municipalities
    d_muni <- make_from_baf("IL", "INCPLACE_CDP", "VTD", year = 2020) |>
        mutate(GEOID = paste0(censable::match_fips("IL"), vtd)) |>
        select(-vtd)
    il_shp <- left_join(il_shp, d_muni, by = "GEOID") |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, .after = county)

    # add the enacted plan via geo_match with SLDL shapefile
    sldl_shp <- st_read(here("data-raw/IL/sldl_2020/tl_2022_17_sldl.shp"), quiet = TRUE) |>
        st_transform(st_crs(il_shp))
    il_shp <- il_shp |>
        mutate(shd_2020 = as.integer(sldl_shp$SLDLST)[
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

    il_shp <- il_shp |>
        fix_geo_assignment(muni)

    # fill any remaining NA enacted values using adjacency (prevents extra district in redist_map)
    il_shp <- fill_na_enacted(il_shp, shd_2020)

    write_rds(il_shp, here(shp_path), compress = "gz")
    cli_process_done()
} else {
    il_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {.strong IL} shapefile")
}
