###############################################################################
# diagnose_shd_failures.R
#
# Diagnoses where each SHD pipeline job failed (or succeeded) by inspecting:
#   1. Output file existence (determines pipeline stage reached)
#   2. SLDL input shapefile existence (prep input validation)
#   3. shp_vtd.rds data quality (NA enacted %, dup GEOIDs, max pop, row count)
#   4. _map.rds adjacency connectivity check
#   5. SLURM error logs (if present in logs/)
#
# The four pipeline stages, in order:
#   prep  -> produces  data-out/{ST}_{YR}/shp_vtd.rds
#   setup -> produces  data-out/{ST}_{YR}/{slug}_map.rds
#   sim   -> produces  data-out/{ST}_{YR}/{slug}_plans.rds
#   stats -> produces  data-out/{ST}_{YR}/{slug}_stats.csv
#
# Usage (from project root):
#   source("analyses/diagnose_shd_failures.R")
#
# Output:
#   Printed summary tables in the console
#   data-out/combined/shd_diagnosis.csv   (one row per state-decade job)
###############################################################################

suppressMessages({
    library(dplyr)
    library(readr)
    library(tidyr)
    library(stringr)
    library(cli)
    library(here)
})

# ── Configuration ─────────────────────────────────────────────────────────────

# Set to TRUE to read shp_vtd.rds for data quality checks (slower but more
# informative; recommended when diagnosing prep/setup failures)
INSPECT_SHP <- TRUE

# ── State manifests (mirrors run_all_shd.sh) ─────────────────────────────────

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
states_2020 <- c(
    "AK", "AL", "AR", "AZ", "CO", "CT", "DE", "FL", "GA",
    "IA", "ID", "IL", "IN", "KS", "KY", "LA", "MA", "MD",
    "MI", "MN", "MO", "MS", "MT", "NC", "ND", "NH", "NJ",
    "NM", "NV", "NY", "OH", "OK", "PA", "RI", "SC", "SD",
    "TN", "TX", "UT", "VA", "VT", "WA", "WI", "WV", "WY"
)

# ── Known heuristics for failure classification ───────────────────────────────
# Based on cluster-errors.md and prior run analysis

ISLAND_STATES    <- c("AK", "HI")
POP_TOO_LARGE    <- c("NH", "VT", "ND", "MT", "WY")  # VTDs too coarse for small chambers
MEMORY_LARGE     <- c("CA")                            # ~80 districts; matrix too big
PRECLEARANCE     <- c("AL", "AK", "AZ", "GA", "LA", "MS", "SC", "TX", "VA")  # VRA Sec. 5

FIPS <- c(
    AL="01", AK="02", AZ="04", AR="05", CA="06", CO="08", CT="09", DE="10",
    FL="12", GA="13", HI="15", IA="19", ID="16", IL="17", IN="18", KS="20",
    KY="21", LA="22", MA="25", MD="24", ME="23", MI="26", MN="27", MO="29",
    MS="28", MT="30", NC="37", ND="38", NH="33", NJ="34", NM="35", NV="32",
    NY="36", OH="39", OK="40", OR="41", PA="42", RI="44", SC="45", SD="46",
    TN="47", TX="48", UT="49", VA="51", VT="50", WA="53", WI="55", WV="54",
    WY="56"
)

# ── Helper: SLDL shapefile path for each decade ───────────────────────────────

sldl_shp_path <- function(state, year) {
    f <- FIPS[state]
    if (year == 2010) {
        here("data-raw", state, "sldl_2010", paste0("tl_2013_", f, "_sldl.shp"))
    } else if (year == 2020) {
        here("data-raw", state, "sldl_2020", paste0("tl_2022_", f, "_sldl.shp"))
    } else {
        here("data-raw", state, "sldl_2000", paste0("tl_2010_", f, "_sldl10.shp"))
    }
}

# ── Helper: Check output file existence ──────────────────────────────────────

check_outputs <- function(state, year) {
    out  <- here("data-out", paste0(state, "_", year))
    slug <- paste0(state, "_shd_", year)
    list(
        state      = state,
        year       = year,
        slug       = slug,
        has_shp    = file.exists(file.path(out, "shp_vtd.rds")),
        has_map    = file.exists(file.path(out, paste0(slug, "_map.rds"))),
        has_plans  = file.exists(file.path(out, paste0(slug, "_plans.rds"))),
        has_stats  = file.exists(file.path(out, paste0(slug, "_stats.csv"))),
        has_sldl   = file.exists(sldl_shp_path(state, year)),
        shp_bytes  = if (file.exists(file.path(out, "shp_vtd.rds")))
                         file.info(file.path(out, "shp_vtd.rds"))$size else NA_real_,
        map_bytes  = if (file.exists(file.path(out, paste0(slug, "_map.rds"))))
                         file.info(file.path(out, paste0(slug, "_map.rds")))$size else NA_real_
    )
}

# ── Helper: Inspect shp_vtd.rds for data quality ─────────────────────────────
# Checks: row count, NA% in enacted column, duplicated GEOIDs, max VTD pop.
# A large NA% means geo_match failed to assign enacted districts.
# A large nrow for a small state means VTD duplication (known 2010 bug).

inspect_shp <- function(state, year) {
    shp_path     <- here("data-out", paste0(state, "_", year), "shp_vtd.rds")
    enacted_col  <- paste0("shd_", year)
    empty        <- list(shp_nrow = NA_integer_, shp_na_enacted_pct = NA_real_,
                         shp_dup_geoid = NA, shp_max_pop = NA_real_,
                         shp_n_districts = NA_integer_, shp_note = NA_character_)
    if (!file.exists(shp_path)) return(empty)

    tryCatch({
        shp <- read_rds(shp_path)

        if (!enacted_col %in% names(shp)) {
            return(modifyList(empty, list(
                shp_nrow = nrow(shp),
                shp_note = paste0("missing column '", enacted_col, "'")
            )))
        }

        # GEOID column detection
        geoid_col <- intersect(c("GEOID", "GEOID10", "GEOID20"), names(shp))[1]

        list(
            shp_nrow            = nrow(shp),
            shp_na_enacted_pct  = round(100 * mean(is.na(shp[[enacted_col]])), 1),
            shp_dup_geoid       = if (!is.na(geoid_col))
                                      anyDuplicated(shp[[geoid_col]]) > 0 else NA,
            shp_max_pop         = if ("pop" %in% names(shp))
                                      max(shp$pop, na.rm = TRUE) else NA_real_,
            shp_n_districts     = length(unique(na.omit(shp[[enacted_col]]))),
            shp_note            = NA_character_
        )
    }, error = function(e) {
        modifyList(empty, list(shp_note = conditionMessage(e)))
    })
}

# ── Helper: Inspect _map.rds for adjacency connectivity ──────────────────────
# A disconnected adjacency graph causes redist_smc() to fail immediately.

inspect_map <- function(state, year) {
    slug     <- paste0(state, "_shd_", year)
    map_path <- here("data-out", paste0(state, "_", year), paste0(slug, "_map.rds"))
    empty    <- list(map_n_units = NA_integer_, map_n_districts = NA_integer_,
                     map_adj_connected = NA, map_note = NA_character_)
    if (!file.exists(map_path)) return(empty)

    tryCatch({
        map_obj     <- read_rds(map_path)
        enacted_col <- paste0("shd_", year)
        adj         <- attr(map_obj, "adj")

        # BFS connectivity check
        connected <- tryCatch({
            if (is.null(adj) || length(adj) == 0) {
                NA
            } else {
                n       <- length(adj)
                visited <- logical(n)
                queue   <- 1L
                visited[1L] <- TRUE
                while (length(queue) > 0) {
                    v     <- queue[1L]; queue <- queue[-1L]
                    nbrs  <- adj[[v]] + 1L          # 0-indexed to 1-indexed
                    new   <- nbrs[!visited[nbrs]]
                    visited[new] <- TRUE
                    queue <- c(queue, new)
                }
                all(visited)
            }
        }, error = function(e) NA)

        list(
            map_n_units       = nrow(map_obj),
            map_n_districts   = if (enacted_col %in% names(map_obj))
                                    length(unique(map_obj[[enacted_col]])) else NA_integer_,
            map_adj_connected = connected,
            map_note          = NA_character_
        )
    }, error = function(e) {
        modifyList(empty, list(map_note = conditionMessage(e)))
    })
}

# ── Helper: Scan SLURM error logs ────────────────────────────────────────────
# Logs are named logs/shd_XXXX_N.err or logs/shd_{decade}s_XXXX_N.err.
# Each log file should contain the analysis slug in its header line.

scan_log <- function(state, year) {
    log_dir <- here("logs")
    if (!dir.exists(log_dir)) return(NA_character_)

    slug      <- paste0(state, "_shd_", year)
    log_files <- list.files(log_dir, pattern = "\\.err$", full.names = TRUE)
    if (length(log_files) == 0) return(NA_character_)

    # Error keywords to extract
    err_rx <- paste(
        "Error", "error", "FAILED", "Killed", "Segfault", "segfault",
        "cannot allocate", "pop too large", "stopifnot", "subscript out of bounds",
        "object .* not found", "no applicable method",
        sep = "|"
    )

    for (f in log_files) {
        lines <- tryCatch(readLines(f, warn = FALSE), error = function(e) character(0))
        if (!any(grepl(slug, lines, fixed = TRUE))) next
        err_lines <- lines[grepl(err_rx, lines, perl = TRUE)]
        if (length(err_lines) > 0) {
            return(paste(head(trimws(err_lines), 3L), collapse = " | "))
        }
    }
    NA_character_
}

# ── Helper: Classify suspected failure cause ─────────────────────────────────

classify_cause <- function(state, year, stage_reached, has_sldl,
                           shp_na_pct, shp_dup_geoid, shp_max_pop,
                           map_adj_connected) {
    if (stage_reached == "complete") return("OK")

    causes <- character(0)

    # Known structural issues (from cluster-errors.md)
    if (state %in% ISLAND_STATES)
        causes <- c(causes, "island_adjacency")

    if (state %in% POP_TOO_LARGE)
        causes <- c(causes, "pop_too_large_vtd")

    if (state %in% MEMORY_LARGE && stage_reached %in% c("sim_failed", "setup_failed"))
        causes <- c(causes, "memory_large_chamber")

    # Stage-specific inference
    if (stage_reached == "prep_failed") {
        if (!isTRUE(has_sldl))
            causes <- c(causes, "missing_sldl_shp")
        else
            causes <- c(causes, "prep_error_see_log")
    }

    if (stage_reached == "setup_failed") {
        if (isTRUE(shp_dup_geoid))
            causes <- c(causes, "dup_geoid_row_explosion")
        if (!is.na(shp_na_pct) && shp_na_pct > 20)
            causes <- c(causes, sprintf("geo_match_failed_%.0f_pct_NA", shp_na_pct))
        if (!is.na(shp_max_pop) && shp_max_pop > 50000 && state %in% POP_TOO_LARGE)
            causes <- c(causes, "vtd_pop_exceeds_target")
        if (length(causes) == 0)
            causes <- c(causes, "setup_error_see_log")
    }

    if (stage_reached == "sim_failed") {
        if (isTRUE(!map_adj_connected))
            causes <- c(causes, "disconnected_adjacency")
        if (length(causes) == 0)
            causes <- c(causes, "smc_error_see_log")
    }

    if (stage_reached == "stats_failed")
        causes <- c(causes, "stats_error_see_log")

    if (length(causes) == 0) causes <- "unknown"
    paste(causes, collapse = "; ")
}

# ── Build job manifest ────────────────────────────────────────────────────────

cli_h1("SHD Pipeline Failure Diagnosis")
cli_alert_info("Scanning output files for {length(states_2000) + length(states_2010) + length(states_2020)} state-decade jobs...")

all_checks <- bind_rows(
    lapply(states_2000, check_outputs, year = 2000),
    lapply(states_2010, check_outputs, year = 2010),
    lapply(states_2020, check_outputs, year = 2020)
)

# Pipeline stage reached
all_checks <- all_checks |>
    mutate(stage_reached = case_when(
        has_stats  ~ "complete",
        has_plans  ~ "stats_failed",
        has_map    ~ "sim_failed",
        has_shp    ~ "setup_failed",
        TRUE       ~ "prep_failed"
    ))

# ── Inspect shp and map files ─────────────────────────────────────────────────

if (INSPECT_SHP) {
    cli_alert_info("Inspecting shp_vtd.rds files (set INSPECT_SHP = FALSE to skip)...")
    shp_data <- all_checks |>
        filter(has_shp) |>
        rowwise() |>
        mutate(shp_info = list(inspect_shp(state, year))) |>
        ungroup() |>
        mutate(
            shp_nrow           = sapply(shp_info, `[[`, "shp_nrow"),
            shp_na_enacted_pct = sapply(shp_info, `[[`, "shp_na_enacted_pct"),
            shp_dup_geoid      = sapply(shp_info, `[[`, "shp_dup_geoid"),
            shp_max_pop        = sapply(shp_info, `[[`, "shp_max_pop"),
            shp_n_districts    = sapply(shp_info, `[[`, "shp_n_districts"),
            shp_note           = sapply(shp_info, `[[`, "shp_note")
        ) |>
        select(slug, shp_nrow, shp_na_enacted_pct, shp_dup_geoid,
               shp_max_pop, shp_n_districts, shp_note)

    all_checks <- left_join(all_checks, shp_data, by = "slug")
} else {
    all_checks <- all_checks |>
        mutate(shp_nrow = NA_integer_, shp_na_enacted_pct = NA_real_,
               shp_dup_geoid = NA, shp_max_pop = NA_real_,
               shp_n_districts = NA_integer_, shp_note = NA_character_)
}

cli_alert_info("Inspecting _map.rds adjacency...")
map_data <- all_checks |>
    filter(has_map) |>
    rowwise() |>
    mutate(map_info = list(inspect_map(state, year))) |>
    ungroup() |>
    mutate(
        map_n_units       = sapply(map_info, `[[`, "map_n_units"),
        map_n_districts   = sapply(map_info, `[[`, "map_n_districts"),
        map_adj_connected = sapply(map_info, `[[`, "map_adj_connected"),
        map_note          = sapply(map_info, `[[`, "map_note")
    ) |>
    select(slug, map_n_units, map_n_districts, map_adj_connected, map_note)

all_checks <- left_join(all_checks, map_data, by = "slug")

# ── Scan logs ────────────────────────────────────────────────────────────────

cli_alert_info("Scanning SLURM logs in logs/ ...")
all_checks <- all_checks |>
    rowwise() |>
    mutate(log_error = scan_log(state, year)) |>
    ungroup()

# ── Classify suspected causes ─────────────────────────────────────────────────

all_checks <- all_checks |>
    rowwise() |>
    mutate(suspected_cause = classify_cause(
        state, year, stage_reached, has_sldl,
        shp_na_enacted_pct, shp_dup_geoid, shp_max_pop,
        map_adj_connected
    )) |>
    ungroup()

# ── Console output ────────────────────────────────────────────────────────────

cli_h2("1. Overall completion by decade")
stage_by_year <- all_checks |>
    count(year, stage_reached) |>
    pivot_wider(names_from = stage_reached, values_from = n, values_fill = 0L) |>
    arrange(year)
print(stage_by_year)

cli_h2("2. Completion rate by decade")
all_checks |>
    group_by(year) |>
    summarise(
        total    = n(),
        complete = sum(stage_reached == "complete"),
        pct_done = round(100 * complete / total, 0),
        .groups  = "drop"
    ) |>
    print()

cli_h2("3. Failed jobs with bottleneck stage and suspected cause")
failed <- all_checks |>
    filter(stage_reached != "complete") |>
    select(state, year, stage_reached, has_sldl, suspected_cause,
           shp_nrow, shp_na_enacted_pct, shp_dup_geoid, shp_max_pop,
           map_adj_connected, log_error) |>
    arrange(stage_reached, state, year)
print(failed, n = 200)

cli_h2("4. States that failed ALL three decades")
all_failures <- all_checks |>
    group_by(state) |>
    summarise(
        n_decades    = n(),
        n_complete   = sum(stage_reached == "complete"),
        stages       = paste(sort(unique(stage_reached)), collapse = ", "),
        causes       = paste(sort(unique(suspected_cause[suspected_cause != "OK"])), collapse = "; "),
        .groups      = "drop"
    ) |>
    filter(n_complete == 0) |>
    arrange(state)
print(all_failures, n = 50)

cli_h2("5. Preclearance (VRA Section 5) state coverage")
prec_table <- all_checks |>
    filter(state %in% PRECLEARANCE) |>
    select(state, year, stage_reached, suspected_cause) |>
    arrange(state, year)
print(prec_table, n = 50)

cli_h2("6. Top suspected failure causes")
all_checks |>
    filter(stage_reached != "complete") |>
    separate_rows(suspected_cause, sep = "; ") |>
    count(suspected_cause, sort = TRUE) |>
    print()

cli_h2("7. shp_vtd.rds quality flags (for prep-completed states)")
shp_flags <- all_checks |>
    filter(has_shp) |>
    mutate(
        flag_high_na_enacted = !is.na(shp_na_enacted_pct) & shp_na_enacted_pct > 10,
        flag_dup_geoid       = isTRUE(shp_dup_geoid),
        flag_pop_too_large   = !is.na(shp_max_pop) & shp_max_pop > 50000
    ) |>
    filter(flag_high_na_enacted | flag_dup_geoid | flag_pop_too_large | !is.na(shp_note)) |>
    select(state, year, shp_nrow, shp_na_enacted_pct, shp_dup_geoid,
           shp_max_pop, shp_n_districts, shp_note)
if (nrow(shp_flags) == 0) {
    cli_alert_success("No data quality flags in any shp_vtd.rds")
} else {
    print(shp_flags, n = 50)
}

cli_h2("8. Log errors found")
log_hits <- all_checks |>
    filter(!is.na(log_error)) |>
    select(state, year, stage_reached, log_error)
if (nrow(log_hits) == 0) {
    cli_alert_warning("No SLURM error logs found in logs/ — run on cluster to capture errors")
} else {
    print(log_hits, n = 50)
}

# ── Save ─────────────────────────────────────────────────────────────────────

dir.create(here("data-out/combined"), showWarnings = FALSE, recursive = TRUE)
out_path <- here("data-out/combined/shd_diagnosis.csv")

out_tbl <- all_checks |>
    select(state, year, slug, stage_reached, suspected_cause,
           has_shp, has_map, has_plans, has_stats, has_sldl,
           shp_bytes, map_bytes,
           shp_nrow, shp_na_enacted_pct, shp_dup_geoid, shp_max_pop,
           shp_n_districts, shp_note,
           map_n_units, map_n_districts, map_adj_connected, map_note,
           log_error) |>
    mutate(across(where(is.logical), as.character))

write_csv(out_tbl, out_path)
cli_alert_success("Saved diagnosis to {.file {out_path}} ({nrow(out_tbl)} rows)")
