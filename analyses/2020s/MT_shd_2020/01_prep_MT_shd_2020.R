###############################################################################
# Download and prepare BLOCK-LEVEL data for `MT_shd_2020` analysis
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
cli_process_start("Building block data for {.pkg MT_shd_2020}")

path_data <- build_block_data("MT", "data-raw/MT", year = 2020)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path  <- "data-out/MT_2020/shp_block.rds"
perim_path <- "data-out/MT_2020/perim.rds"
dir.create(here("data-out/MT_2020"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {
    cli_process_start("Preparing {.strong MT} block shapefile")

    mt_shp <- read_csv(here(path_data), col_types = cols(GEOID20 = "c")) |>
        join_block_shapefile(year = 2020) |>
        st_transform(EPSG$MT) |>
        rename_with(function(x) gsub("[0-9.]", "", x), starts_with("GEOID"))

    # add municipalities from PL BAF at block level
    baf_raw <- PL94171::pl_get_baf("MT",
        cache_to = here("data-raw/MT/MT_baf.rds"))
    d_muni <- baf_raw$INCPLACE_CDP |>
        tidyr::unite("muni", -BLOCKID, sep = "") |>
        mutate(muni = na_if(muni, "NA")) |>
        rename(GEOID = BLOCKID)
    mt_shp <- mt_shp |>
        left_join(d_muni, by = "GEOID") |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, .after = county)

    # add the enacted plan from 2022 BAF at block level
    mt_shp <- mt_shp |>
        left_join(leg_from_baf("MT", to = "block"), by = "GEOID")

    # fix labeling
    mt_shp$state <- "MT"

    # eliminate empty shapes
    mt_shp <- mt_shp |> filter(!st_is_empty(geometry))

    # Create perimeters
    redistmetrics::prep_perims(shp = mt_shp,
        perim_path = here(perim_path)) |>
        invisible()

    # simplify geometry
    if (requireNamespace("rmapshaper", quietly = TRUE)) {
        mt_shp <- rmapshaper::ms_simplify(mt_shp, keep = 0.05,
            keep_shapes = TRUE) |>
            suppressWarnings()
    }

    # create adjacency graph
    mt_shp$adj <- redist.adjacency(mt_shp)

    # connect islands / disconnected precincts
    mt_shp$adj <- mt_shp$adj |>
        add_edge(suggest_neighbors(mt_shp, mt_shp$adj)$x,
                 suggest_neighbors(mt_shp, mt_shp$adj)$y)

    mt_shp <- mt_shp |>
        fix_geo_assignment(muni)

    write_rds(mt_shp, here(shp_path), compress = "gz")
    cli_process_done()
} else {
    mt_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {.strong MT} block shapefile")
}
