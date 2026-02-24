###############################################################################
# Download and prepare BLOCK-LEVEL data for `ND_shd_2010` analysis
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

# Build block-level data (Census 2010 blocks + VTD election crosswalk)
cli_process_start("Building block data for {.pkg ND_shd_2010}")

path_data <- build_block_data("ND", "data-raw/ND", year = 2010)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path  <- "data-out/ND_2010/shp_block.rds"
perim_path <- "data-out/ND_2010/perim.rds"
dir.create(here("data-out/ND_2010"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {
    cli_process_start("Preparing {.strong ND} block shapefile")

    nd_shp <- read_csv(here(path_data), col_types = cols(GEOID10 = "c")) |>
        join_block_shapefile(year = 2010) |>
        st_transform(EPSG$ND) |>
        rename_with(function(x) gsub("[0-9.]", "", x), starts_with("GEOID"))

    # add municipalities from Census 2010 BAF at block level
    baf_10 <- get_baf_10("ND",
        cache_to = here("data-raw/ND/ND_baf_10.rds"))
    d_muni <- baf_10[["INCPLACE_CDP"]] |>
        tidyr::unite("muni", -BLOCKID, sep = "") |>
        mutate(muni = na_if(muni, "NA")) |>
        rename(GEOID = BLOCKID)
    nd_shp <- nd_shp |>
        left_join(d_muni, by = "GEOID") |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, .after = county)

    # add the enacted plan via geo_match with SLDL shapefile (post-2010 plans from TIGER 2013)
    sldl_shp <- st_read(here("data-raw/ND/sldl_2010/tl_2013_38_sldl.shp"), quiet = TRUE) |>
        st_transform(st_crs(nd_shp))
    nd_shp <- nd_shp |>
        mutate(shd_2010 = as.integer(sldl_shp$SLDLST)[
            geo_match(nd_shp, sldl_shp, method = "area")])

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

    # fill any remaining NA enacted values using adjacency
    nd_shp <- fill_na_enacted(nd_shp, shd_2010)

    write_rds(nd_shp, here(shp_path), compress = "gz")
    cli_process_done()
} else {
    nd_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {.strong ND} block shapefile")
}
