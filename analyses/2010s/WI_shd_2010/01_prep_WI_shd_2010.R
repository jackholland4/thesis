###############################################################################
# Download and prepare data for `WI_shd_2010` analysis
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

# Download necessary files for analysis -----
cli_process_start("Downloading files for {.pkg WI_shd_2010}")

path_data <- download_redistricting_file("WI", "data-raw/WI", year = 2010)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path <- "data-out/WI_2010/shp_vtd.rds"
perim_path <- "data-out/WI_2010/perim.rds"
dir.create(here("data-out/WI_2010"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {
    cli_process_start("Preparing {.strong WI} shapefile")
    # read in redistricting data
    wi_shp <- read_csv(here(path_data)) |>
        join_vtd_shapefile(year = 2010) |>
        st_transform(EPSG$WI) |>
        rename_with(function(x) gsub("[0-9.]", "", x), starts_with("GEOID"))

    # add municipalities
    d_muni <- make_from_baf("WI", "INCPLACE_CDP", "VTD", year = 2010) |>
        mutate(GEOID = paste0(censable::match_fips("WI"), vtd)) |>
        select(-vtd)
    wi_shp <- left_join(wi_shp, d_muni, by = "GEOID") |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, .after = county)

    # add the enacted plan via geo_match with SLDL shapefile (post-2010 plans from TIGER 2013)
    sldl_shp <- st_read(here("data-raw/WI/sldl_2010/tl_2013_55_sldl.shp"), quiet = TRUE) |>
        st_transform(st_crs(wi_shp))
    wi_shp <- wi_shp |>
        mutate(shd_2010 = as.integer(sldl_shp$SLDLST)[
            geo_match(wi_shp, sldl_shp, method = "area")])

    # fix labeling
    wi_shp$state <- "WI"

    # eliminate empty shapes
    wi_shp <- wi_shp |> filter(!st_is_empty(geometry))

    # Create perimeters
    redistmetrics::prep_perims(shp = wi_shp,
        perim_path = here(perim_path)) |>
        invisible()

    # simplify geometry
    if (requireNamespace("rmapshaper", quietly = TRUE)) {
        wi_shp <- rmapshaper::ms_simplify(wi_shp, keep = 0.05,
            keep_shapes = TRUE) |>
            suppressWarnings()
    }

    # create adjacency graph
    wi_shp$adj <- redist.adjacency(wi_shp)

    # connect islands / disconnected precincts
    wi_shp$adj <- wi_shp$adj |>
        add_edge(suggest_neighbors(wi_shp, wi_shp$adj)$x,
                 suggest_neighbors(wi_shp, wi_shp$adj)$y)

    wi_shp <- wi_shp |>
        fix_geo_assignment(muni)

    # fill any remaining NA enacted values using adjacency (prevents extra district in redist_map)
    wi_shp <- fill_na_enacted(wi_shp, shd_2010)

    write_rds(wi_shp, here(shp_path), compress = "gz")
    cli_process_done()
} else {
    wi_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {.strong WI} shapefile")
}
