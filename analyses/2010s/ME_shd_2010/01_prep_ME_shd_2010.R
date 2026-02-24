###############################################################################
# Download and prepare BLOCK-LEVEL data for `ME_shd_2010` analysis
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
cli_process_start("Building block data for {.pkg ME_shd_2010}")

path_data <- build_block_data("ME", "data-raw/ME", year = 2010)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path  <- "data-out/ME_2010/shp_block.rds"
perim_path <- "data-out/ME_2010/perim.rds"
dir.create(here("data-out/ME_2010"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {
    cli_process_start("Preparing {.strong ME} block shapefile")

    me_shp <- read_csv(here(path_data), col_types = cols(GEOID10 = "c")) |>
        join_block_shapefile(year = 2010) |>
        st_transform(EPSG$ME) |>
        rename_with(function(x) gsub("[0-9.]", "", x), starts_with("GEOID"))

    # add municipalities from Census 2010 BAF at block level
    baf_10 <- get_baf_10("ME",
        cache_to = here("data-raw/ME/ME_baf_10.rds"))
    d_muni <- baf_10[["INCPLACE_CDP"]] |>
        tidyr::unite("muni", -BLOCKID, sep = "") |>
        mutate(muni = na_if(muni, "NA")) |>
        rename(GEOID = BLOCKID)
    me_shp <- me_shp |>
        left_join(d_muni, by = "GEOID") |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, .after = county)

    # add the enacted plan via geo_match with SLDL shapefile (post-2010 plans from TIGER 2013)
    sldl_shp <- st_read(here("data-raw/ME/sldl_2010/tl_2013_23_sldl.shp"), quiet = TRUE) |>
        st_transform(st_crs(me_shp))
    me_shp <- me_shp |>
        mutate(shd_2010 = as.integer(sldl_shp$SLDLST)[
            geo_match(me_shp, sldl_shp, method = "area")])

    # fix labeling
    me_shp$state <- "ME"

    # eliminate empty shapes
    me_shp <- me_shp |> filter(!st_is_empty(geometry))

    # Create perimeters
    redistmetrics::prep_perims(shp = me_shp,
        perim_path = here(perim_path)) |>
        invisible()

    # simplify geometry
    if (requireNamespace("rmapshaper", quietly = TRUE)) {
        me_shp <- rmapshaper::ms_simplify(me_shp, keep = 0.05,
            keep_shapes = TRUE) |>
            suppressWarnings()
    }

    # create adjacency graph
    me_shp$adj <- redist.adjacency(me_shp)

    # connect islands / disconnected precincts
    me_shp$adj <- me_shp$adj |>
        add_edge(suggest_neighbors(me_shp, me_shp$adj)$x,
                 suggest_neighbors(me_shp, me_shp$adj)$y)

    me_shp <- me_shp |>
        fix_geo_assignment(muni)

    # fill any remaining NA enacted values using adjacency
    me_shp <- fill_na_enacted(me_shp, shd_2010)

    write_rds(me_shp, here(shp_path), compress = "gz")
    cli_process_done()
} else {
    me_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {.strong ME} block shapefile")
}
