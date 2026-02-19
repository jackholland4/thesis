#' Download a file
#'
#' Backend-agnostic (currently `curl`)
#'
#' @param url a URL
#' @param path a file path
#' @param overwrite should the file at path be overwritten if it already exists? Default is FALSE.
#'
#' @returns the `curl` request
download <- function(url, path, overwrite = FALSE) {
  dir <- dirname(path)
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  if (!file.exists(path) || overwrite) {
    curl::curl_download(url = url, destfile = path)
  } else {
    cli::cli_alert_info(paste0("File already downloaded at ", path, ". Set `overwrite = TRUE` to overwrite."))
    list(status_code = 200)
  }
}

#' Download redistricting data file
#'
#' @param abbr the state to download
#' @param folder will be downloaded to `folder/{abbr}_2020_*.csv`
#' @param type either `vtd` or `block`, depending on availability at
#'   <https://github.com/alarm-redist/census-2020/tree/main/census-vest-2020>.
#' @param overwrite if TRUE, download even if a file exists
#'
#' @returns the path to file
#' @export
download_redistricting_file <- function(abbr, folder, type = "vtd", overwrite = FALSE, year = 2020) {
  if (year %in% c(2010, 2020)) {
    abbr <- tolower(abbr)
    url <- str_glue(
      "https://raw.githubusercontent.com/alarm-redist/census-2020/",
      "main/census-vest-{year}/{abbr}_{year}_{type}.csv"
    )
  } else if (year %in% c(1990, 2000)) {
    abbr <- toupper(abbr)
    url <- stringr::str_glue(
      'https://raw.githubusercontent.com/alarm-redist/census-2020/',
      'refs/heads/road/road-{year}/{abbr}_{year}.csv'
    )
  } else {
    stop("Year must be 1990, 2000, 2010, or 2020.")
  }
  path <- paste0(folder, "/", basename(url))

  if (!file.exists(path) || overwrite) {
    resp <- download(url, path, overwrite)
    # CTK: when download uses curl, it provides a clean error
    # if (resp$status_code == "404") {
    #   stop("No files available for ", abbr)
    # }
  }
  path
}

#' Add precinct shapefile geometry to downloaded data
#'
#' @param data the output of e.g. [download_redistricting_file]
#' @param year the year, either 2020 (default) or 2010
#'
#' @returns the joined data
#' @export
join_vtd_shapefile <- function(data, year = 2020) {
  if (year == 2020) {
    geom_d <- PL94171::pl_get_vtd(data$state[1]) |>
      select(GEOID20, area_land = ALAND20, area_water = AWATER20, geometry)
    left_join(data, geom_d, by = "GEOID20") |>
      sf::st_as_sf()
  } else if (year == 2010) {
    state_fp <- censable::match_fips(data$state[1])
    counties <- censable::fips_2010 |>
      dplyr::filter(state == state_fp) |>
      dplyr::pull(county)

    files <- lapply(
      counties,
      function(cty) {
        temp <- tempfile(fileext = ".zip")
        download(
          url = str_glue("https://www2.census.gov/geo/tiger/TIGER2010/VTD/2010/tl_2010_{state_fp}{cty}_vtd10.zip"),
          path = temp
        )
        unzip(temp, exdir = dirname(temp))
        sf::st_read(str_glue("{dirname(temp)}/tl_2010_{state_fp}{cty}_vtd10.shp"), quiet = TRUE) |>
          dplyr::transmute(
            GEOID10 = str_c(str_sub(GEOID10, end = 5), str_pad_l0(str_sub(GEOID10, start = 6), 6)),
            area_land = ALAND10, area_water = AWATER10,
            geometry = geometry
          )
      }
    )


    geom_d <- do.call("rbind", files) |>
      # some states have multi-part VTD geometries as separate rows; union them
      # to avoid row explosion that causes spurious "out of memory" errors
      dplyr::group_by(GEOID10) |>
      dplyr::summarize(area_land = sum(area_land), area_water = sum(area_water),
                       geometry = sf::st_union(geometry)) |>
      dplyr::ungroup()
    left_join(data |> mutate(GEOID10 = paste0(
      str_pad_l0(state, 2), str_pad_l0(county, 3), str_pad_l0(vtd, 6)
    )), geom_d, by = "GEOID10") |>
      sf::st_as_sf()
  } else if (year == 2000) {
    tract_states <- c(
      'AK', 'AZ', 'CA', 'CO', 'FL', 'KY', 'MT', 'ND', 'OH', 'OR', 'SD', 'WI'
    )

    if (censable::match_abb(data$state[1]) %in% tract_states) {
      data |>
        left_join(
          tinytiger::tt_tracts(
            state = censable::match_fips(data$state[1]),
            year = year
          ) |>
            rename(GEOID = CTIDFP00)
        ) |>
        sf::st_as_sf()
    } else {
      data |>
        left_join(
          tinytiger::tt_voting_districts(
            state = censable::match_fips(data$state[1]),
            year = year
          ) |>
            mutate(
              GEOID = paste0(STATEFP00, COUNTYFP00, str_pad(VTDST00, 6, "left", "0"))
            )
        ) |>
        sf::st_as_sf()
    }

  } else if (year == 1990) {
    shp <- dataverse::get_file_by_name(
      filename = stringr::str_glue("{censable::match_fips(data$state[1])}_tracts.gpkg"),
      dataset = "10.7910/DVN/L60KIF"
    )
    tf <- tempfile(fileext = ".gpkg")
    writeBin(shp, tf)

    data |>
      left_join(
        sf::st_read(tf, quiet = TRUE)
      ) |>
      dplyr::mutate(state = censable::match_abb(.data$state)) |>
      sf::st_as_sf()
  }
}

#' Add Census block geometry to block-level downloaded data
#'
#' Use instead of [join_vtd_shapefile()] when `download_redistricting_file()`
#' was called with `type = "block"`. Required for states where individual VTDs
#' exceed the per-district population target (NH, ME, MT, ND, etc.).
#'
#' @param data the output of [download_redistricting_file()] with `type = "block"`
#' @param year the year (2020 supported)
#'
#' @returns the joined sf data frame at block level
#' @export
join_block_shapefile <- function(data, year = 2020) {
  if (year == 2020) {
    state_fp <- censable::match_fips(data$state[1])
    geom_d <- tigris::blocks(state = state_fp, year = year, progress_bar = FALSE) |>
      dplyr::select(GEOID20, area_land = ALAND20, area_water = AWATER20, geometry)
    left_join(data, geom_d, by = "GEOID20") |>
      sf::st_as_sf()
  } else {
    cli::cli_abort("join_block_shapefile() only supports year = 2020.")
  }
}

#' Download or build block-level redistricting data
#'
#' First tries the ALARM pre-built block CSV (available for CA, HI, ME, OR).
#' For states without a pre-built file (NH, MT, ND, etc.), builds block-level
#' data by combining Census block demographics from [censable::build_dec()] with
#' VTD-level election data disaggregated to blocks by population weight.
#'
#' @param state state abbreviation
#' @param folder folder to cache raw and output files
#' @param year the year (2020 supported)
#' @param overwrite if TRUE, rebuild even if a cached file exists
#'
#' @returns path to the block-level CSV, invisibly
#' @export
build_block_data <- function(state, folder, year = 2020, overwrite = FALSE) {
  state_abb <- toupper(state)
  state_fp  <- censable::match_fips(state_abb)
  dir.create(here(folder), showWarnings = FALSE, recursive = TRUE)

  # 1. Try the ALARM pre-built block CSV first (CA, HI, ME, OR have these)
  path_alarm <- tryCatch(
    download_redistricting_file(state_abb, folder, type = "block", year = year),
    error = function(e) NULL
  )
  if (!is.null(path_alarm) && file.exists(path_alarm)) {
    cli::cli_alert_success("Using ALARM pre-built block data for {.pkg {state_abb}}")
    return(invisible(path_alarm))
  }

  # 2. Fall back: build from Census + VTD election crosswalk
  path_out <- file.path(folder, str_glue("{tolower(state_abb)}_{year}_block.csv"))
  if (file.exists(here(path_out)) && !overwrite) {
    cli::cli_alert_info("Cached at {.file {path_out}}. Set {.code overwrite = TRUE} to rebuild.")
    return(invisible(path_out))
  }

  cli::cli_process_start("Building block-level data for {.pkg {state_abb}} from Census")

  # block-level population + demographics from decennial Census
  # censable::build_dec() returns the same column names used in ALARM CSVs
  block_dem <- censable::build_dec(
    geography = "block",
    state     = state_abb,
    year      = year,
    geometry  = FALSE
  ) |>
    dplyr::rename(GEOID20 = GEOID) |>
    dplyr::mutate(
      state  = state_abb,
      county = stringr::str_sub(GEOID20, 3, 5)
    )

  # VTD election data from ALARM for disaggregation
  path_vtd <- download_redistricting_file(state_abb, folder, type = "vtd", year = year)
  vtd_elect <- readr::read_csv(here(path_vtd), col_types = readr::cols(GEOID20 = "c")) |>
    dplyr::select(GEOID20, ndv, nrv) |>
    dplyr::mutate(vtd_short = stringr::str_sub(GEOID20, 3))  # strip 2-char state prefix

  # block → VTD crosswalk from PL BAF
  baf <- PL94171::pl_get_baf(
    state_abb,
    cache_to = here(file.path(folder, str_glue("{state_abb}_baf.rds")))
  )
  vtd_map <- baf$VTD |>
    dplyr::transmute(
      GEOID20   = BLOCKID,
      vtd_short = paste0(COUNTYFP, str_pad_l0(DISTRICT, 6))
    )

  # population-weighted disaggregation of VTD election data to blocks
  out <- block_dem |>
    dplyr::left_join(vtd_map, by = "GEOID20") |>
    dplyr::left_join(vtd_elect, by = "vtd_short") |>
    dplyr::group_by(vtd_short) |>
    dplyr::mutate(
      vtd_pop = sum(pop, na.rm = TRUE),
      ndv = dplyr::if_else(vtd_pop > 0, ndv * pop / vtd_pop, 0),
      nrv = dplyr::if_else(vtd_pop > 0, nrv * pop / vtd_pop, 0)
    ) |>
    dplyr::ungroup() |>
    dplyr::select(-vtd_short, -vtd_pop)

  readr::write_csv(out, here(path_out))
  cli::cli_process_done()
  invisible(path_out)
}

# reproducible code for making EPSG lookup
make_epsg_table <- function() {
  raw <- as_tibble(rgdal::make_EPSG()) |>
    select(code, note)
  state_regex <- paste0("(", paste0(datasets::state.name, collapse = "|"), ")")
  epsg_regex <- str_glue("NAD83(\\(HARN\\))? / {state_regex} ?[A-Za-z. ]*$")
  epsg_d <- filter(
    raw, (code > 2500L & code < 2900L) | (code > 3300L & code < 3400L),
    str_detect(note, epsg_regex)
  ) |>
    mutate(
      state = str_match(note, epsg_regex)[, 3],
      priority = str_detect(note, "HARN") + str_detect(note, "Central")
    ) |>
    group_by(state) |>
    arrange(desc(priority)) |>
    slice(1) |>
    ungroup() |>
    select(code, state) |>
    rows_insert(tibble(code = 2784L, state = "Hawaii"), by = "state") |>
    arrange(state)

  codes <- as.list(epsg_d$code)
  names(codes) <- datasets::state.abb
  codes
}

EPSG <- read_rds(here("R/epsg.rds"))


#' Remove an edge
#'
#' @param adj an adjacency graph
#' @param v1 numeric indices of the first vertex in each edge
#' @param v2 numeric indices of the second vertex in each edge
#' @param zero if `TRUE`, the entries of `adj` are zero-indexed
remove_edge <- function(adj, v1, v2, zero = TRUE) {
  geomander::subtract_edge(adj = adj, v1 = v1, v2 = v2, zero = zero)
}

#' Retally with VEST
#'
#' Uses VEST crosswalk. Code mostly copied from [census-2020](https://github.com/alarm-redist/census-2020/blob/main/R/00_build_vest.R)
#'
#' @param cvap cvap data at 2010 block level
#' @param state state abbreviation
#'
#' @return tibble with vtd level data
#' @export
#' @md
#' @examples
#' cvap <- cvap::cvap_distribute_censable("DE") |> select(GEOID, starts_with("cvap"))
#' vtd <- vest_crosswalk(cvap, "DE")
vest_crosswalk <- function(cvap, state) {
  cw_zip <- dataverse::get_file_by_name("block10block20_crosswalks.zip", "10.7910/DVN/T9VMJO")
  cw_zip_path <- withr::local_tempfile(fileext = ".zip")
  writeBin(cw_zip, cw_zip_path)
  unz_path <- file.path(dirname(cw_zip_path), "block1020_crosswalks")
  utils::unzip(cw_zip_path, exdir = unz_path, overwrite = TRUE)

  proc_raw_cw <- function(raw) {
    fields <- str_split(raw, ",")
    purrr::map_dfr(fields, function(x) {
      if (length(x) <= 1) {
        return(tibble())
      }
      tibble(
        GEOID_to = x[1],
        GEOID = x[seq(2, length(x), by = 2L)],
        int_land = parse_number(x[seq(3, length(x), by = 2L)])
      )
    })
  }

  vest_cw_raw <- read_lines(glue::glue("{unz_path}/block1020_crosswalk_{censable::match_fips(state)}.csv"))
  vest_cw <- proc_raw_cw(vest_cw_raw)
  cw <- pl_crosswalk(toupper(state))
  vest_cw <- left_join(vest_cw, select(cw, -int_land), by = c("GEOID", "GEOID_to"))
  rt <- pl_retally(cvap, crosswalk = vest_cw)

  baf <- pl_get_baf(toupper(state), "VTD") |>
    purrr::pluck(1) |>
    rename(GEOID = BLOCKID) |>
    mutate(
      STATEFP = censable::match_fips(state),
      GEOID20 = paste0(STATEFP, COUNTYFP, DISTRICT)
    )

  rt <- rt |> left_join(baf, by = "GEOID")

  # agg
  vtd <- rt |>
    select(-GEOID, -area_land, -area_water) |>
    group_by(GEOID20) |>
    summarize(
      across(where(is.character), .fns = unique),
      across(where(is.numeric), .fns = sum)
    ) |>
    relocate(GEOID20, .before = everything()) |>
    relocate(STATEFP, .before = COUNTYFP) |>
    mutate(across(where(is.numeric), round, 2))

  vtd
}


load_plans <- function(state) {
  plans <<- read_rds(here(str_glue("data-out/{state}_2020/{state}_cd_2020_plans.rds")))
}
load_map <- function(state) {
  map <<- read_rds(here(str_glue("data-out/{state}_2020/{state}_cd_2020_map.rds")))
}
rename_cd <- function(plans) {
  m <- as.matrix(plans)
  new_names <- colnames(m)
  new_names[1] <- "cd_2020"
  colnames(m) <- new_names
  plans$draw <- forcats::fct_recode(plans$draw, cd_2020 = "cd")
  plans
}

open_state <- function(state, type = "cd", year = 2020) {
  state <- str_to_upper(state)
  year <- as.character(as.integer(year))
  slug <- str_glue("{state}_{type}_{year}")

  if (requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable()) {
    files <- fs::dir_ls(path = stringr::str_glue('analyses/{slug}/'))
    lapply(c(files, rev(files)[-1]), rstudioapi::navigateToFile)
  }

  invisible(NULL)
}


Mode <- function(v) {
  if (all(is.na(v))) {
    return(v[1])
  }
  v <- v[!is.na(v)]
  uv <- unique(v)
  uv[which.max(tabulate(match(v, uv)))][1]
}

str_pad_l0 <- function(string, width) {
  stringr::str_pad(string = string, width = width, side = "left", pad = "0")
}
