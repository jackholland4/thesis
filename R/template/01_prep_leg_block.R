###############################################################################
# Download and prepare data for ```SLUG``` analysis (block-level)
# ``COPYRIGHT``
###############################################################################
# Block-level template: use when VTDs are too coarse for the district targets
# (e.g. NH SHD ~3,300/district, ME/MT/ND SHD ~8,000-10,500/district).
# build_block_data() automatically uses ALARM's pre-built block CSV if one
# exists (CA, HI, ME, OR); otherwise it builds from censable + VTD crosswalk.
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

stopifnot(utils::packageVersion("redist") >= "5.0.0.1")

# Download / build block-level data -----
cli_process_start("Downloading files for {.pkg ``SLUG``}")

# build_block_data() tries the ALARM pre-built block CSV first;
# falls back to censable::build_dec() + VTD election crosswalk if unavailable.
path_data <- build_block_data("``STATE``", "data-raw/``STATE``", year = ``YEAR``)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path  <- "data-out/``STATE``_``YEAR``/shp_block.rds"
perim_path <- "data-out/``STATE``_``YEAR``/perim.rds"
dir.create(here("data-out/``STATE``_``YEAR``"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {
    cli_process_start("Preparing {.strong ``STATE``} block shapefile")

    # read block data and join Census block geometry
    ``state``_shp <- read_csv(here(path_data), col_types = cols(GEOID20 = "c")) |>
        join_block_shapefile(year = ``YEAR``) |>
        st_transform(EPSG$``STATE``) |>
        rename_with(function(x) gsub("[0-9.]", "", x), starts_with("GEOID"))

    # add muni, previous-decade SSD/SHD directly from the 2020 PL BAF
    # each block is already assigned to exactly one geography — no aggregation needed
    baf_raw <- PL94171::pl_get_baf("``STATE``",
        cache_to = here("data-raw/``STATE``/``STATE``_baf.rds"))

    d_muni <- baf_raw$INCPLACE_CDP |>
        tidyr::unite("muni", -BLOCKID, sep = "") |>
        mutate(muni = na_if(muni, "NA")) |>
        rename(GEOID = BLOCKID)

    d_ssd <- baf_raw$SLDU |>
        tidyr::unite("ssd_``OLDYEAR``", -BLOCKID, sep = "") |>
        mutate(ssd_``OLDYEAR`` = as.integer(na_if(ssd_``OLDYEAR``, "NA"))) |>
        rename(GEOID = BLOCKID)

    d_shd <- baf_raw$SLDL |>
        tidyr::unite("shd_``OLDYEAR``", -BLOCKID, sep = "") |>
        mutate(shd_``OLDYEAR`` = as.integer(na_if(shd_``OLDYEAR``, "NA"))) |>
        rename(GEOID = BLOCKID)

    ``state``_shp <- ``state``_shp |>
        left_join(d_muni, by = "GEOID") |>
        left_join(d_ssd,  by = "GEOID") |>
        left_join(d_shd,  by = "GEOID") |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, ssd_``OLDYEAR``, .after = county) |>
        relocate(muni, county_muni, shd_``OLDYEAR``, .after = county)

    # add the enacted plan at block level
    ``state``_shp <- ``state``_shp |>
        left_join(y = leg_from_baf(state = "``STATE``", to = "block"), by = "GEOID")

    # TODO any additional columns or data you want to add should go here

    # Create perimeters
    redistmetrics::prep_perims(shp = ``state``_shp,
        perim_path = here(perim_path)) |>
        invisible()

    # geometry simplification — optional at block level; remove if it causes issues
    if (requireNamespace("rmapshaper", quietly = TRUE)) {
        ``state``_shp <- rmapshaper::ms_simplify(``state``_shp, keep = 0.05,
            keep_shapes = TRUE) |>
            suppressWarnings()
    }

    # create adjacency graph
    ``state``_shp$adj <- adjacency(``state``_shp)

    # connect islands / disconnected precincts
    # TODO remove if ccm output is already all 1s
    ``state``_shp$adj <- ``state``_shp$adj |>
        add_edge(suggest_neighbors(``state``_shp, ``state``_shp$adj)$x,
                 suggest_neighbors(``state``_shp, ``state``_shp$adj)$y)

    # check max number of connected components (1 = fully connected)
    ccm(``state``_shp$adj, ``state``_shp$ssd_2020)
    ccm(``state``_shp$adj, ``state``_shp$shd_2020)

    ``state``_shp <- ``state``_shp |>
        fix_geo_assignment(muni)

    write_rds(``state``_shp, here(shp_path), compress = "gz")
    cli_process_done()
} else {
    ``state``_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {.strong ``STATE``} block shapefile")
}

# TODO visualize the enacted maps using:
# redistio::draw(``state``_shp, ``state``_shp$ssd_2020)
# redistio::draw(``state``_shp, ``state``_shp$shd_2020)
