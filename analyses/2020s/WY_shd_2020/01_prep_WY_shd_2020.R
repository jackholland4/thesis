###############################################################################
# Download and prepare BLOCK-LEVEL data for `WY_shd_2020` analysis
# VTDs are too coarse for this state's small district targets; using Census blocks.
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

# Build block-level data (ALARM pre-built CSV if available; else Census + VTD crosswalk)
cli_process_start("Building block data for {.pkg WY_shd_2020}")

path_data <- build_block_data("WY", "data-raw/WY", year = 2020)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path  <- "data-out/WY_2020/shp_block.rds"
perim_path <- "data-out/WY_2020/perim.rds"
dir.create(here("data-out/WY_2020"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {
    cli_process_start("Preparing {.strong WY} block shapefile")

    wy_shp <- read_csv(here(path_data), col_types = cols(GEOID20 = "c")) |>
        join_block_shapefile(year = 2020) |>
        st_transform(EPSG$WY) |>
        rename_with(function(x) gsub("[0-9.]", "", x), starts_with("GEOID"))

    # add municipalities from PL BAF at block level
    baf_raw <- PL94171::pl_get_baf("WY",
        cache_to = here("data-raw/WY/WY_baf.rds"))
    d_muni <- baf_raw$INCPLACE_CDP |>
        tidyr::unite("muni", -BLOCKID, sep = "") |>
        mutate(muni = na_if(muni, "NA")) |>
        rename(GEOID = BLOCKID)
    wy_shp <- wy_shp |>
        left_join(d_muni, by = "GEOID") |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, .after = county)

    # add the enacted plan from 2022 BAF at block level
    wy_shp <- wy_shp |>
        left_join(leg_from_baf("WY", to = "block"), by = "GEOID")

    # fix labeling
    wy_shp$state <- "WY"

    # eliminate empty shapes
    wy_shp <- wy_shp |> filter(!st_is_empty(geometry))

    # Create perimeters
    redistmetrics::prep_perims(shp = wy_shp,
        perim_path = here(perim_path)) |>
        invisible()

    # simplify geometry
    if (requireNamespace("rmapshaper", quietly = TRUE)) {
        wy_shp <- rmapshaper::ms_simplify(wy_shp, keep = 0.05,
            keep_shapes = TRUE) |>
            suppressWarnings()
    }

    # create adjacency graph
    wy_shp$adj <- redist.adjacency(wy_shp)

    # connect islands / disconnected precincts
    wy_shp$adj <- wy_shp$adj |>
        add_edge(suggest_neighbors(wy_shp, wy_shp$adj)$x,
                 suggest_neighbors(wy_shp, wy_shp$adj)$y)

    wy_shp <- wy_shp |>
        fix_geo_assignment(muni)

    write_rds(wy_shp, here(shp_path), compress = "gz")
    cli_process_done()
} else {
    wy_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {.strong WY} block shapefile")
}
