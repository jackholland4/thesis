###############################################################################
# Download and prepare BLOCK-LEVEL data for `NH_shd_2010` analysis
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
cli_process_start("Building block data for {.pkg NH_shd_2010}")

path_data <- build_block_data("NH", "data-raw/NH", year = 2010)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path  <- "data-out/NH_2010/shp_block.rds"
perim_path <- "data-out/NH_2010/perim.rds"
dir.create(here("data-out/NH_2010"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {
    cli_process_start("Preparing {.strong NH} block shapefile")

    nh_shp <- read_csv(here(path_data), col_types = cols(GEOID10 = "c")) |>
        join_block_shapefile(year = 2010) |>
        st_transform(EPSG$NH) |>
        rename_with(function(x) gsub("[0-9.]", "", x), starts_with("GEOID"))

    # add municipalities from Census 2010 BAF at block level
    baf_10 <- get_baf_10("NH",
        cache_to = here("data-raw/NH/NH_baf_10.rds"))
    d_muni <- baf_10[["INCPLACE_CDP"]] |>
        tidyr::unite("muni", -BLOCKID, sep = "") |>
        mutate(muni = na_if(muni, "NA")) |>
        rename(GEOID = BLOCKID)
    nh_shp <- nh_shp |>
        left_join(d_muni, by = "GEOID") |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, .after = county)

    # add the enacted plan via geo_match with SLDL shapefile (post-2010 plans from TIGER 2013)
    sldl_shp <- st_read(here("data-raw/NH/sldl_2010/tl_2013_33_sldl.shp"), quiet = TRUE) |>
        st_transform(st_crs(nh_shp))
    nh_shp <- nh_shp |>
        mutate(shd_2010 = as.integer(sldl_shp$SLDLST)[
            geo_match(nh_shp, sldl_shp, method = "area")])

    # fix labeling
    nh_shp$state <- "NH"

    # eliminate empty shapes
    nh_shp <- nh_shp |> filter(!st_is_empty(geometry))

    # Create perimeters
    redistmetrics::prep_perims(shp = nh_shp,
        perim_path = here(perim_path)) |>
        invisible()

    # simplify geometry
    if (requireNamespace("rmapshaper", quietly = TRUE)) {
        nh_shp <- rmapshaper::ms_simplify(nh_shp, keep = 0.05,
            keep_shapes = TRUE) |>
            suppressWarnings()
    }

    # create adjacency graph
    nh_shp$adj <- redist.adjacency(nh_shp)

    # connect islands / disconnected precincts
    nh_shp$adj <- nh_shp$adj |>
        add_edge(suggest_neighbors(nh_shp, nh_shp$adj)$x,
                 suggest_neighbors(nh_shp, nh_shp$adj)$y)

    nh_shp <- nh_shp |>
        fix_geo_assignment(muni)

    # fill any remaining NA enacted values using adjacency
    nh_shp <- fill_na_enacted(nh_shp, shd_2010)

    write_rds(nh_shp, here(shp_path), compress = "gz")
    cli_process_done()
} else {
    nh_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {.strong NH} block shapefile")
}
