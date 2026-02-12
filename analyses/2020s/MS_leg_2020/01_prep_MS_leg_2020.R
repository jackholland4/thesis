###############################################################################
# Download and prepare data for `MS_leg_2020` analysis
# © ALARM Project, February 2026
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

# Download necessary files for analysis -----
cli_process_start("Downloading files for {.pkg MS_leg_2020}")

path_data <- download_redistricting_file("MS", "data-raw/MS", year = 2020)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path <- "data-out/MS_2020/shp_vtd.rds"
perim_path <- "data-out/MS_2020/perim.rds"
dir.create(here("data-out/MS_2020"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {
    cli_process_start("Preparing {.strong MS} shapefile")
    # read in redistricting data
    ms_shp <- read_csv(here(path_data), col_types = cols(GEOID20 = "c")) |>
        join_vtd_shapefile(year = 2020) |>
        st_transform(EPSG$MS)  |>
        rename_with(function(x) gsub("[0-9.]", "", x), starts_with("GEOID"))

    # add municipalities
    d_muni <- make_from_baf("MS", "INCPLACE_CDP", "VTD", year = 2020)  |>
        mutate(GEOID = paste0(censable::match_fips("MS"), vtd)) |>
        select(-vtd)
    d_ssd <- make_from_baf("MS", "SLDU", "VTD", year = 2020)  |>
        transmute(GEOID = paste0(censable::match_fips("MS"), vtd),
            ssd_2010 = as.integer(sldu))
    d_shd <- make_from_baf("MS", "SLDL", "VTD", year = 2020)  |>
        transmute(GEOID = paste0(censable::match_fips("MS"), vtd),
            shd_2010 = as.integer(sldl))

    ms_shp <- ms_shp |>
        left_join(d_muni, by = "GEOID") |>
        left_join(d_ssd, by = "GEOID") |>
        left_join(d_shd, by = "GEOID") |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, ssd_2010, .after = county) |>
        relocate(muni, county_muni, shd_2010, .after = county)

    # add the enacted plan
    ms_shp <- ms_shp |>
        left_join(y = leg_from_baf(state = "MS"), by = "GEOID")

    # Create perimeters in case shapes are simplified
    redistmetrics::prep_perims(shp = ms_shp,
        perim_path = here(perim_path)) |>
        invisible()

    # simplifies geometry for faster processing, plotting, and smaller shapefiles
    if (requireNamespace("rmapshaper", quietly = TRUE)) {
        ms_shp <- rmapshaper::ms_simplify(ms_shp, keep = 0.05,
            keep_shapes = TRUE) |>
            suppressWarnings()
    }

    # create adjacency graph
    ms_shp$adj <- adjacency(ms_shp)

    # check max number of connected components
    ccm(ms_shp$adj, ms_shp$ssd_2020)
    ccm(ms_shp$adj, ms_shp$shd_2020)

    ms_shp <- ms_shp |>
        fix_geo_assignment(muni)

    write_rds(ms_shp, here(shp_path), compress = "gz")
    cli_process_done()
} else {
    ms_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {.strong MS} shapefile")
}
