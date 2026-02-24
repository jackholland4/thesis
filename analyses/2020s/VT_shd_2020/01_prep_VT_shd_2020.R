###############################################################################
# Download and prepare BLOCK-LEVEL data for `VT_shd_2020` analysis
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
cli_process_start("Building block data for {.pkg VT_shd_2020}")

path_data <- build_block_data("VT", "data-raw/VT", year = 2020)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path  <- "data-out/VT_2020/shp_block.rds"
perim_path <- "data-out/VT_2020/perim.rds"
dir.create(here("data-out/VT_2020"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {
    cli_process_start("Preparing {.strong VT} block shapefile")

    vt_shp <- read_csv(here(path_data), col_types = cols(GEOID20 = "c")) |>
        join_block_shapefile(year = 2020) |>
        st_transform(EPSG$VT) |>
        rename_with(function(x) gsub("[0-9.]", "", x), starts_with("GEOID"))

    # add municipalities from PL BAF at block level
    baf_raw <- PL94171::pl_get_baf("VT",
        cache_to = here("data-raw/VT/VT_baf.rds"))
    d_muni <- baf_raw$INCPLACE_CDP |>
        tidyr::unite("muni", -BLOCKID, sep = "") |>
        mutate(muni = na_if(muni, "NA")) |>
        rename(GEOID = BLOCKID)
    vt_shp <- vt_shp |>
        left_join(d_muni, by = "GEOID") |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, .after = county)

    # add the enacted plan from 2022 BAF at block level
    vt_shp <- vt_shp |>
        left_join(leg_from_baf("VT", to = "block"), by = "GEOID")

    # fix labeling
    vt_shp$state <- "VT"

    # eliminate empty shapes
    vt_shp <- vt_shp |> filter(!st_is_empty(geometry))

    # Create perimeters
    redistmetrics::prep_perims(shp = vt_shp,
        perim_path = here(perim_path)) |>
        invisible()

    # simplify geometry
    if (requireNamespace("rmapshaper", quietly = TRUE)) {
        vt_shp <- rmapshaper::ms_simplify(vt_shp, keep = 0.05,
            keep_shapes = TRUE) |>
            suppressWarnings()
    }

    # create adjacency graph
    vt_shp$adj <- redist.adjacency(vt_shp)

    # connect islands / disconnected precincts
    vt_shp$adj <- vt_shp$adj |>
        add_edge(suggest_neighbors(vt_shp, vt_shp$adj)$x,
                 suggest_neighbors(vt_shp, vt_shp$adj)$y)

    vt_shp <- vt_shp |>
        fix_geo_assignment(muni)

    write_rds(vt_shp, here(shp_path), compress = "gz")
    cli_process_done()
} else {
    vt_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {.strong VT} block shapefile")
}
