###############################################################################
# Batch-generate state house (SHD) analysis folders for 2000s, 2010s, and 2020s
#
# This script creates 01_prep, 02_setup, and 03_sim scripts for each
# state-decade combination, using SLDL boundary shapefiles for enacted plan
# assignment. Correct TIGER vintages per decade:
#   2000s (post-2000 plans): census_sldl_2010/ → tl_2010_XX_sldl10 (SLDLST10)
#   2010s (post-2010 plans): census_sldl_2013/ → tl_2013_XX_sldl  (SLDLST)
#   2020s (post-2020 plans): census_sldl_2022/ → tl_2022_XX_sldl  (SLDLST)
#
# Usage: source("analyses/00_generate_shd_analyses.R")
###############################################################################

library(here)
library(stringr)
library(cli)

# State lists -----
# 2000s: 48 states (excluding NE unicameral; AK lacks VTD data for 2000)
states_2000 <- c(
    "AL", "AR", "AZ", "CA", "CO", "CT", "DE", "FL", "GA", "HI",
    "IA", "ID", "IL", "IN", "KS", "KY", "LA", "MA", "MD", "ME",
    "MI", "MN", "MO", "MS", "MT", "NC", "ND", "NH", "NJ", "NM",
    "NV", "NY", "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN",
    "TX", "UT", "VA", "VT", "WA", "WI", "WV", "WY"
)

states_2010 <- c(
    "AK", "AL", "AR", "AZ", "CA", "CO", "CT", "DE", "FL", "GA",
    "HI", "IA", "ID", "IL", "IN", "KS", "KY", "LA", "MA", "MD",
    "ME", "MI", "MN", "MO", "MS", "MT", "NC", "ND", "NH", "NJ",
    "NM", "NV", "NY", "OH", "OK", "OR", "PA", "RI", "SC", "SD",
    "TN", "TX", "UT", "VA", "VT", "WA", "WI", "WV", "WY"
)

# 2020s: 45 states (excluding NE unicameral; CA, HI, ME, OR lack VTD data)
states_2020 <- c(
    "AK", "AL", "AR", "AZ", "CO", "CT", "DE", "FL", "GA",
    "IA", "ID", "IL", "IN", "KS", "KY", "LA", "MA", "MD",
    "MI", "MN", "MO", "MS", "MT", "NC", "ND", "NH", "NJ",
    "NM", "NV", "NY", "OH", "OK", "PA", "RI", "SC", "SD",
    "TN", "TX", "UT", "VA", "VT", "WA", "WI", "WV", "WY"
)

# FIPS lookup
fips_lookup <- c(
    AL = "01", AK = "02", AZ = "04", AR = "05", CA = "06", CO = "08",
    CT = "09", DE = "10", FL = "12", GA = "13", HI = "15", IA = "19",
    ID = "16", IL = "17", IN = "18", KS = "20", KY = "21", LA = "22",
    MA = "25", MD = "24", ME = "23", MI = "26", MN = "27", MO = "29",
    MS = "28", MT = "30", NC = "37", ND = "38", NH = "33", NJ = "34",
    NM = "35", NV = "32", NY = "36", OH = "39", OK = "40", OR = "41",
    PA = "42", PR = "72", RI = "44", SC = "45", SD = "46", TN = "47",
    TX = "48", UT = "49", VA = "51", VT = "50", WA = "53", WI = "55",
    WV = "54", WY = "56"
)

# --- Script templates ---

make_prep_2010 <- function(state, fips) {
    str_glue('
###############################################################################
# Download and prepare data for `{state}_shd_2010` analysis
###############################################################################

suppressMessages({{
    library(dplyr)
    library(readr)
    library(sf)
    library(redist)
    library(geomander)
    library(cli)
    library(here)
    devtools::load_all() # load utilities
}})

# Download necessary files for analysis -----
cli_process_start("Downloading files for {{.pkg {state}_shd_2010}}")

path_data <- download_redistricting_file("{state}", "data-raw/{state}", year = 2010)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path <- "data-out/{state}_2010/shp_vtd.rds"
perim_path <- "data-out/{state}_2010/perim.rds"
dir.create(here("data-out/{state}_2010"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {{
    cli_process_start("Preparing {{.strong {state}}} shapefile")
    # read in redistricting data
    {tolower(state)}_shp <- read_csv(here(path_data)) |>
        join_vtd_shapefile(year = 2010) |>
        st_transform(EPSG${state}) |>
        rename_with(function(x) gsub("[0-9.]", "", x), starts_with("GEOID"))

    # add municipalities
    d_muni <- make_from_baf("{state}", "INCPLACE_CDP", "VTD", year = 2010) |>
        mutate(GEOID = paste0(censable::match_fips("{state}"), vtd)) |>
        select(-vtd)
    {tolower(state)}_shp <- left_join({tolower(state)}_shp, d_muni, by = "GEOID") |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, .after = county)

    # add the enacted plan via geo_match with SLDL shapefile (post-2010 plans from TIGER 2013)
    sldl_shp <- st_read(here("data-raw/{state}/sldl_2010/tl_2013_{fips}_sldl.shp"), quiet = TRUE) |>
        st_transform(st_crs({tolower(state)}_shp))
    {tolower(state)}_shp <- {tolower(state)}_shp |>
        mutate(shd_2010 = as.integer(sldl_shp$SLDLST)[
            geo_match({tolower(state)}_shp, sldl_shp, method = "area")])

    # fix labeling
    {tolower(state)}_shp$state <- "{state}"

    # eliminate empty shapes
    {tolower(state)}_shp <- {tolower(state)}_shp |> filter(!st_is_empty(geometry))

    # Create perimeters
    redistmetrics::prep_perims(shp = {tolower(state)}_shp,
        perim_path = here(perim_path)) |>
        invisible()

    # simplify geometry
    if (requireNamespace("rmapshaper", quietly = TRUE)) {{
        {tolower(state)}_shp <- rmapshaper::ms_simplify({tolower(state)}_shp, keep = 0.05,
            keep_shapes = TRUE) |>
            suppressWarnings()
    }}

    # create adjacency graph
    {tolower(state)}_shp$adj <- redist.adjacency({tolower(state)}_shp)

    {tolower(state)}_shp <- {tolower(state)}_shp |>
        fix_geo_assignment(muni)

    write_rds({tolower(state)}_shp, here(shp_path), compress = "gz")
    cli_process_done()
}} else {{
    {tolower(state)}_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {{.strong {state}}} shapefile")
}}
')
}

make_prep_2020 <- function(state, fips) {
    str_glue('
###############################################################################
# Download and prepare data for `{state}_shd_2020` analysis
###############################################################################

suppressMessages({{
    library(dplyr)
    library(readr)
    library(sf)
    library(redist)
    library(geomander)
    library(cli)
    library(here)
    library(tinytiger)
    devtools::load_all() # load utilities
}})

# Download necessary files for analysis -----
cli_process_start("Downloading files for {{.pkg {state}_shd_2020}}")

path_data <- download_redistricting_file("{state}", "data-raw/{state}", year = 2020)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path <- "data-out/{state}_2020/shp_vtd.rds"
perim_path <- "data-out/{state}_2020/perim.rds"
dir.create(here("data-out/{state}_2020"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {{
    cli_process_start("Preparing {{.strong {state}}} shapefile")
    # read in redistricting data
    {tolower(state)}_shp <- read_csv(here(path_data), col_types = cols(GEOID20 = "c")) |>
        join_vtd_shapefile(year = 2020) |>
        st_transform(EPSG${state}) |>
        rename_with(function(x) gsub("[0-9.]", "", x), starts_with("GEOID"))

    # add municipalities
    d_muni <- make_from_baf("{state}", "INCPLACE_CDP", "VTD", year = 2020) |>
        mutate(GEOID = paste0(censable::match_fips("{state}"), vtd)) |>
        select(-vtd)
    {tolower(state)}_shp <- left_join({tolower(state)}_shp, d_muni, by = "GEOID") |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, .after = county)

    # add the enacted plan via geo_match with SLDL shapefile
    sldl_shp <- st_read(here("data-raw/{state}/sldl_2020/tl_2022_{fips}_sldl.shp"), quiet = TRUE) |>
        st_transform(st_crs({tolower(state)}_shp))
    {tolower(state)}_shp <- {tolower(state)}_shp |>
        mutate(shd_2020 = as.integer(sldl_shp$SLDLST)[
            geo_match({tolower(state)}_shp, sldl_shp, method = "area")])

    # fix labeling
    {tolower(state)}_shp$state <- "{state}"

    # eliminate empty shapes
    {tolower(state)}_shp <- {tolower(state)}_shp |> filter(!st_is_empty(geometry))

    # Create perimeters
    redistmetrics::prep_perims(shp = {tolower(state)}_shp,
        perim_path = here(perim_path)) |>
        invisible()

    # simplify geometry
    if (requireNamespace("rmapshaper", quietly = TRUE)) {{
        {tolower(state)}_shp <- rmapshaper::ms_simplify({tolower(state)}_shp, keep = 0.05,
            keep_shapes = TRUE) |>
            suppressWarnings()
    }}

    # create adjacency graph
    {tolower(state)}_shp$adj <- redist.adjacency({tolower(state)}_shp)

    {tolower(state)}_shp <- {tolower(state)}_shp |>
        fix_geo_assignment(muni)

    write_rds({tolower(state)}_shp, here(shp_path), compress = "gz")
    cli_process_done()
}} else {{
    {tolower(state)}_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {{.strong {state}}} shapefile")
}}
')
}

make_prep_2000 <- function(state, fips) {
    str_glue('
###############################################################################
# Download and prepare data for `{state}_shd_2000` analysis
###############################################################################

suppressMessages({{
    library(dplyr)
    library(readr)
    library(sf)
    library(redist)
    library(geomander)
    library(baf)
    library(cli)
    library(here)
    devtools::load_all() # load utilities
}})

# Download necessary files for analysis -----
cli_process_start("Downloading files for {{.pkg {state}_shd_2000}}")

path_data <- download_redistricting_file("{state}", "data-raw/{state}", year = 2000)

cli_process_done()

# Compile raw data into a final shapefile for analysis -----
shp_path <- "data-out/{state}_2000/shp_vtd.rds"
perim_path <- "data-out/{state}_2000/perim.rds"
dir.create(here("data-out/{state}_2000"), showWarnings = FALSE, recursive = TRUE)

if (!file.exists(here(shp_path))) {{
    cli_process_start("Preparing {{.strong {state}}} shapefile")
    # read in redistricting data
    {tolower(state)}_shp <- read_csv(here(path_data), col_types = cols(GEOID = "c")) |>
        join_vtd_shapefile(year = 2000) |>
        st_transform(EPSG${state})

    {tolower(state)}_shp <- {tolower(state)}_shp |>
        rename(muni = place) |>
        mutate(county_muni = if_else(is.na(muni), county, str_c(county, muni))) |>
        relocate(muni, county_muni, .after = county)

    # add the enacted plan via geo_match with SLDL shapefile (post-2000 plans from TIGER 2010)
    sldl_shp <- st_read(here("data-raw/{state}/sldl_2000/tl_2010_{fips}_sldl10.shp"), quiet = TRUE) |>
        st_transform(st_crs({tolower(state)}_shp))
    {tolower(state)}_shp <- {tolower(state)}_shp |>
        mutate(shd_2000 = as.integer(sldl_shp$SLDLST10)[
            geo_match({tolower(state)}_shp, sldl_shp, method = "area")])

    # fix labeling
    {tolower(state)}_shp$state <- "{state}"

    # eliminate empty shapes
    {tolower(state)}_shp <- {tolower(state)}_shp |> filter(!st_is_empty(geometry))

    # Create perimeters
    redistmetrics::prep_perims(shp = {tolower(state)}_shp,
        perim_path = here(perim_path)) |>
        invisible()

    # simplify geometry
    if (requireNamespace("rmapshaper", quietly = TRUE)) {{
        {tolower(state)}_shp <- rmapshaper::ms_simplify({tolower(state)}_shp, keep = 0.05,
            keep_shapes = TRUE) |>
            suppressWarnings()
    }}

    # create adjacency graph
    {tolower(state)}_shp$adj <- redist.adjacency({tolower(state)}_shp)

    write_rds({tolower(state)}_shp, here(shp_path), compress = "gz")
    cli_process_done()
}} else {{
    {tolower(state)}_shp <- read_rds(here(shp_path))
    cli_alert_success("Loaded {{.strong {state}}} shapefile")
}}
')
}

make_setup <- function(state, year) {
    str_glue('
###############################################################################
# Set up redistricting simulation for `{state}_shd_{year}`
###############################################################################
cli_process_start("Creating {{.cls redist_map}} object for {{.pkg {state}_shd_{year}}}")

map_shd <- redist_map({tolower(state)}_shp, pop_tol = 0.05,
    existing_plan = shd_{year}, adj = {tolower(state)}_shp$adj)

# make pseudo counties with default settings
map_shd <- map_shd |>
    mutate(pseudo_county = pick_county_muni(map_shd, counties = county, munis = muni,
        pop_muni = get_target(map_shd)))

# Add an analysis name attribute
attr(map_shd, "analysis_name") <- "{state}_SHD_{year}"

# Output the redist_map object
write_rds(map_shd, "data-out/{state}_{year}/{state}_shd_{year}_map.rds", compress = "xz")
cli_process_done()
')
}

make_sim <- function(state, year) {
    str_glue('
###############################################################################
# Simulate plans for `{state}_shd_{year}` SHD
###############################################################################

# Run the simulation -----
cli_process_start("Running simulations for {{.pkg {state}_shd_{year}}}")

set.seed({year})

mh_accept_per_smc <- ceiling(n_distinct(map_shd$shd_{year}) / 3)

plans <- redist_smc(
    map_shd,
    nsims = 2e3, runs = 5,
    counties = pseudo_county,
    sampling_space = "linking_edge",
    ms_params = list(frequency = 1L, mh_accept_per_smc = mh_accept_per_smc),
    split_params = list(splitting_schedule = "any_valid_sizes"),
    verbose = TRUE
)

plans <- plans |>
    group_by(chain) |>
    filter(as.integer(draw) < min(as.integer(draw)) + 2000) |> # thin samples
    ungroup()
plans <- match_numbers(plans, "shd_{year}")

cli_process_done()
cli_process_start("Saving {{.cls redist_plans}} object")

# Output the redist_plans object
write_rds(plans, here("data-out/{state}_{year}/{state}_shd_{year}_plans.rds"), compress = "xz")
cli_process_done()

# Compute summary statistics -----
cli_process_start("Computing summary statistics for {{.pkg {state}_shd_{year}}}")

plans <- add_summary_stats(plans, map_shd)

# Output the summary statistics
save_summary_stats(plans, "data-out/{state}_{year}/{state}_shd_{year}_stats.csv")

cli_process_done()
')
}

# --- Main generation logic ---

generate_analysis <- function(state, year) {
    fips <- fips_lookup[state]
    state_lower <- tolower(state)
    decade <- paste0(year, "s")
    slug <- str_glue("{state}_shd_{year}")
    analysis_dir <- here("analyses", decade, slug)

    # Create directories
    dir.create(analysis_dir, showWarnings = FALSE, recursive = TRUE)
    dir.create(here("data-out", str_glue("{state}_{year}")), showWarnings = FALSE, recursive = TRUE)
    dir.create(here("data-raw", state), showWarnings = FALSE, recursive = TRUE)

    # Unzip SLDL shapefile (correct TIGER vintage per decade)
    if (year == 2020) {
        zip_path <- here(str_glue("census_sldl_2022/{state}_Leg_2022.zip"))
    } else if (year == 2010) {
        zip_path <- here(str_glue("census_sldl_2013/{state}_Leg_2013.zip"))
    } else {
        # 2000s: use sldl10 files (post-2000 enacted plans) from TIGER 2010
        zip_path <- here(str_glue("census_sldl_2010/{state}_Leg_2010.zip"))
    }
    sldl_dir <- here("data-raw", state, str_glue("sldl_{year}"))
    if (file.exists(zip_path) && !dir.exists(sldl_dir)) {
        dir.create(sldl_dir, showWarnings = FALSE, recursive = TRUE)
        utils::unzip(zip_path, exdir = sldl_dir)
    }

    # Generate scripts
    if (year == 2020) {
        prep_code <- make_prep_2020(state, fips)
    } else if (year == 2010) {
        prep_code <- make_prep_2010(state, fips)
    } else {
        prep_code <- make_prep_2000(state, fips)
    }
    setup_code <- make_setup(state, year)
    sim_code <- make_sim(state, year)

    writeLines(prep_code, file.path(analysis_dir, str_glue("01_prep_{slug}.R")))
    writeLines(setup_code, file.path(analysis_dir, str_glue("02_setup_{slug}.R")))
    writeLines(sim_code, file.path(analysis_dir, str_glue("03_sim_{slug}.R")))

    cli_alert_success("Generated {.pkg {slug}}")
}

# Generate all analyses -----
cli_h1("Generating 2000s state house analyses")
for (st in states_2000) {
    generate_analysis(st, 2000)
}

cli_h1("Generating 2010s state house analyses")
for (st in states_2010) {
    generate_analysis(st, 2010)
}

cli_h1("Generating 2020s state house analyses")
for (st in states_2020) {
    generate_analysis(st, 2020)
}

n_total <- length(states_2000) + length(states_2010) + length(states_2020)
cli_alert_success("Done! Generated {n_total} analysis folders")
