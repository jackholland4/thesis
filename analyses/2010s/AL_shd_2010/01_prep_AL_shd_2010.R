###############################################################################
# Download and prepare BLOCK-LEVEL data for `AL_shd_2010` analysis
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
cli_process_start("Building block data for {.pkg AL_shd_2010}")

path_data <- build_block_data("AL", "data-raw/AL", year = 2010)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path  <- "data-out/AL_2010/shp_block.rds"
perim_path <- "data-out/AL_2010/perim.rds"
dir.create(here("data-out/AL_2010"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {
    cli_process_start("Preparing {.strong AL} block shapefile")

    al_shp <- read_csv(here(path_data), col_types = cols(GEOID10 = "c")) |>
        join_block_shapefile(year = 2010) |>
        st_transform(EPSG$AL) |>
        rename_with(function(x) gsub("[0-9.]", "", x), starts_with("GEOID"))

    # add municipalities from Census 2010 BAF at block level
    baf_10 <- get_baf_10("AL",
        cache_to = here("data-raw/AL/AL_baf_10.rds"))
    d_muni <- baf_10[["INCPLACE_CDP"]] |>
        tidyr::unite("muni", -BLOCKID, sep = "") |>
        mutate(muni = na_if(muni, "NA")) |>
        rename(GEOID = BLOCKID)
    al_shp <- al_shp |>
        left_join(d_muni, by = "GEOID") |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, .after = county)

    # add the enacted plan via geo_match with SLDL shapefile (post-2010 plans from TIGER 2013)
    sldl_shp <- st_read(here("data-raw/AL/sldl_2010/tl_2013_01_sldl.shp"), quiet = TRUE) |>
        st_transform(st_crs(al_shp))
    al_shp <- al_shp |>
        mutate(shd_2010 = as.integer(sldl_shp$SLDLST)[
            geo_match(al_shp, sldl_shp, method = "area")])

    # fix labeling
    al_shp$state <- "AL"

    # eliminate empty shapes
    al_shp <- al_shp |> filter(!st_is_empty(geometry))

    # Create perimeters
    redistmetrics::prep_perims(shp = al_shp,
        perim_path = here(perim_path)) |>
        invisible()

    # simplify geometry
    if (requireNamespace("rmapshaper", quietly = TRUE)) {
        al_shp <- rmapshaper::ms_simplify(al_shp, keep = 0.05,
            keep_shapes = TRUE) |>
            suppressWarnings()
    }

    # create adjacency graph
    al_shp$adj <- redist.adjacency(al_shp)

    # connect islands / disconnected precincts
    al_shp$adj <- al_shp$adj |>
        add_edge(suggest_neighbors(al_shp, al_shp$adj)$x,
                 suggest_neighbors(al_shp, al_shp$adj)$y)

    al_shp <- al_shp |>
        fix_geo_assignment(muni)

    # fill any remaining NA enacted values using adjacency
    al_shp <- fill_na_enacted(al_shp, shd_2010)

    write_rds(al_shp, here(shp_path), compress = "gz")
    cli_process_done()
} else {
    al_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {.strong AL} block shapefile")
}
