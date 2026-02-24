###############################################################################
# Download and prepare BLOCK-LEVEL data for `VT_shd_2010` analysis
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
cli_process_start("Building block data for {.pkg VT_shd_2010}")

path_data <- build_block_data("VT", "data-raw/VT", year = 2010)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path  <- "data-out/VT_2010/shp_block.rds"
perim_path <- "data-out/VT_2010/perim.rds"
dir.create(here("data-out/VT_2010"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {
    cli_process_start("Preparing {.strong VT} block shapefile")

    vt_shp <- read_csv(here(path_data), col_types = cols(GEOID10 = "c")) |>
        join_block_shapefile(year = 2010) |>
        st_transform(EPSG$VT) |>
        rename_with(function(x) gsub("[0-9.]", "", x), starts_with("GEOID"))

    # add municipalities from Census 2010 BAF at block level
    baf_10 <- get_baf_10("VT",
        cache_to = here("data-raw/VT/VT_baf_10.rds"))
    d_muni <- baf_10[["INCPLACE_CDP"]] |>
        tidyr::unite("muni", -BLOCKID, sep = "") |>
        mutate(muni = na_if(muni, "NA")) |>
        rename(GEOID = BLOCKID)
    vt_shp <- vt_shp |>
        left_join(d_muni, by = "GEOID") |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, .after = county)

    # add the enacted plan via geo_match with SLDL shapefile (post-2010 plans from TIGER 2013)
    sldl_shp <- st_read(here("data-raw/VT/sldl_2010/tl_2013_50_sldl.shp"), quiet = TRUE) |>
        st_transform(st_crs(vt_shp))
    vt_shp <- vt_shp |>
        mutate(shd_2010 = as.integer(sldl_shp$SLDLST)[
            geo_match(vt_shp, sldl_shp, method = "area")])

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

    # fill any remaining NA enacted values using adjacency
    vt_shp <- fill_na_enacted(vt_shp, shd_2010)

    write_rds(vt_shp, here(shp_path), compress = "gz")
    cli_process_done()
} else {
    vt_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {.strong VT} block shapefile")
}
