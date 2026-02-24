###############################################################################
# Download and prepare BLOCK-LEVEL data for `ND_shd_2020` analysis
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
cli_process_start("Building block data for {.pkg ND_shd_2020}")

path_data <- build_block_data("ND", "data-raw/ND", year = 2020)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path  <- "data-out/ND_2020/shp_block.rds"
perim_path <- "data-out/ND_2020/perim.rds"
dir.create(here("data-out/ND_2020"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {
    cli_process_start("Preparing {.strong ND} block shapefile")

    nd_shp <- read_csv(here(path_data), col_types = cols(GEOID20 = "c")) |>
        join_block_shapefile(year = 2020) |>
        st_transform(EPSG$ND) |>
        rename_with(function(x) gsub("[0-9.]", "", x), starts_with("GEOID"))

    # add municipalities from PL BAF at block level
    baf_raw <- PL94171::pl_get_baf("ND",
        cache_to = here("data-raw/ND/ND_baf.rds"))
    d_muni <- baf_raw$INCPLACE_CDP |>
        tidyr::unite("muni", -BLOCKID, sep = "") |>
        mutate(muni = na_if(muni, "NA")) |>
        rename(GEOID = BLOCKID)
    nd_shp <- nd_shp |>
        left_join(d_muni, by = "GEOID") |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, .after = county)

    # add the enacted plan from 2022 BAF at block level
    nd_shp <- nd_shp |>
        left_join(leg_from_baf("ND", to = "block"), by = "GEOID")

    # fix labeling
    nd_shp$state <- "ND"

    # eliminate empty shapes
    nd_shp <- nd_shp |> filter(!st_is_empty(geometry))

    # Create perimeters
    redistmetrics::prep_perims(shp = nd_shp,
        perim_path = here(perim_path)) |>
        invisible()

    # simplify geometry
    if (requireNamespace("rmapshaper", quietly = TRUE)) {
        nd_shp <- rmapshaper::ms_simplify(nd_shp, keep = 0.05,
            keep_shapes = TRUE) |>
            suppressWarnings()
    }

    # create adjacency graph
    nd_shp$adj <- redist.adjacency(nd_shp)

    # connect islands / disconnected precincts
    nd_shp$adj <- nd_shp$adj |>
        add_edge(suggest_neighbors(nd_shp, nd_shp$adj)$x,
                 suggest_neighbors(nd_shp, nd_shp$adj)$y)

    nd_shp <- nd_shp |>
        fix_geo_assignment(muni)

    write_rds(nd_shp, here(shp_path), compress = "gz")
    cli_process_done()
} else {
    nd_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {.strong ND} block shapefile")
}
