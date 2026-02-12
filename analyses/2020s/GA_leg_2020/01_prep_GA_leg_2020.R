###############################################################################
# Download and prepare data for `GA_leg_2020` analysis
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
cli_process_start("Downloading files for {.pkg GA_leg_2020}")

path_data <- download_redistricting_file("GA", "data-raw/GA", year = 2020)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path <- "data-out/GA_2020/shp_vtd.rds"
perim_path <- "data-out/GA_2020/perim.rds"
dir.create(here("data-out/GA_2020"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {
    cli_process_start("Preparing {.strong GA} shapefile")
    # read in redistricting data
    ga_shp <- read_csv(here(path_data), col_types = cols(GEOID20 = "c")) |>
        join_vtd_shapefile(year = 2020) |>
        st_transform(EPSG$GA)  |>
        rename_with(function(x) gsub("[0-9.]", "", x), starts_with("GEOID"))

    # add municipalities
    d_muni <- make_from_baf("GA", "INCPLACE_CDP", "VTD", year = 2020)  |>
        mutate(GEOID = paste0(censable::match_fips("GA"), vtd)) |>
        select(-vtd)
    d_ssd <- make_from_baf("GA", "SLDU", "VTD", year = 2020)  |>
        transmute(GEOID = paste0(censable::match_fips("GA"), vtd),
            ssd_2010 = as.integer(sldu))
    d_shd <- make_from_baf("GA", "SLDL", "VTD", year = 2020)  |>
        transmute(GEOID = paste0(censable::match_fips("GA"), vtd),
            shd_2010 = as.integer(sldl))

    ga_shp <- ga_shp |>
        left_join(d_muni, by = "GEOID") |>
        left_join(d_ssd, by = "GEOID") |>
        left_join(d_shd, by = "GEOID") |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, ssd_2010, .after = county) |>
        relocate(muni, county_muni, shd_2010, .after = county)

    # add the enacted plan
    ga_shp <- ga_shp |>
        left_join(y = leg_from_baf(state = "GA"), by = "GEOID")

    # Create perimeters in case shapes are simplified
    redistmetrics::prep_perims(shp = ga_shp,
        perim_path = here(perim_path)) |>
        invisible()

    # simplifies geometry for faster processing, plotting, and smaller shapefiles
    if (requireNamespace("rmapshaper", quietly = TRUE)) {
        ga_shp <- rmapshaper::ms_simplify(ga_shp, keep = 0.05,
            keep_shapes = TRUE) |>
            suppressWarnings()
    }

    # create adjacency graph
    ga_shp$adj <- adjacency(ga_shp)

    # check max number of connected components
    ccm(ga_shp$adj, ga_shp$ssd_2020)
    ccm(ga_shp$adj, ga_shp$shd_2020)

    ga_shp <- ga_shp |>
        fix_geo_assignment(muni)

    write_rds(ga_shp, here(shp_path), compress = "gz")
    cli_process_done()
} else {
    ga_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {.strong GA} shapefile")
}
