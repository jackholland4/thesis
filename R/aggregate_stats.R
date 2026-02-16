#' Aggregate simulation statistics across states and decades
#'
#' Functions for combining plan-level summary statistics across all
#' state-year analyses, adding preclearance metadata, and computing
#' distribution summaries for cross-state regression analysis.

# Section 5 VRA preclearance states (pre-Shelby County v. Holder)
PRECLEARANCE_STATES <- c("AK", "AL", "AZ", "GA", "LA", "MS", "SC", "TX", "VA")

#' Read and combine all stats CSVs from data-out
#'
#' Scans the data-out directory for `*_stats.csv` files, reads each,
#' and adds `state`, `year`, `type`, and `preclearance_status` columns.
#'
#' @param data_out_dir path to the data-out directory. Default uses `here("data-out")`.
#'
#' @return a tibble with all district-level rows across all analyses
#' @export
aggregate_all_stats <- function(data_out_dir = here::here("data-out")) {
    csv_files <- list.files(data_out_dir, pattern = "_stats\\.csv$",
        recursive = TRUE, full.names = TRUE)

    if (length(csv_files) == 0) {
        cli::cli_abort("No stats CSV files found in {.path {data_out_dir}}")
    }

    cli::cli_alert_info("Found {length(csv_files)} stats file{?s}")

    combined <- purrr::map(csv_files, function(f) {
        # Extract metadata from path: e.g., "GA_2020/GA_ssd_2020_stats.csv"
        fname <- basename(f)
        # Pattern: {STATE}_{type}_{year}_stats.csv
        parts <- stringr::str_match(fname, "^([A-Z]{2})_([a-z]+)_(\\d{4})_stats\\.csv$")

        if (is.na(parts[1, 1])) {
            cli::cli_warn("Skipping unrecognized file: {.file {fname}}")
            return(NULL)
        }

        state <- parts[1, 2]
        type <- parts[1, 3]
        year <- as.integer(parts[1, 4])

        cli::cli_alert("Reading {.file {fname}}")
        tb <- readr::read_csv(f, show_col_types = FALSE)
        tb$state <- state
        tb$year <- year
        tb$type <- type
        tb$preclearance_status <- ifelse(state %in% PRECLEARANCE_STATES,
            "preclearance", "non_preclearance")
        tb
    }) |>
        purrr::compact() |>
        purrr::list_rbind()

    combined
}

#' Collapse district-level data to one row per plan
#'
#' Plan-level metrics (replicated across districts) are taken directly;
#' district-level metrics are aggregated to plan means.
#'
#' @param combined_data output of [aggregate_all_stats()]
#'
#' @return a tibble with one row per draw per state-year-type
#' @export
create_plan_summary <- function(combined_data) {
    # Columns that are already plan-level (same value for all districts in a plan)
    plan_level_cols <- c(
        "e_dem", "pbias", "egap",
        "mean_median_diff", "n_competitive", "responsiveness",
        "n_majority_minority", "n_opportunity", "n_influence", "avg_minority_vap",
        "mean_polsby", "sd_polsby",
        "county_splits", "total_county_splits", "muni_splits", "total_muni_splits",
        "plan_dev"
    )
    plan_level_cols <- intersect(plan_level_cols, names(combined_data))

    # District-level columns to aggregate (take mean across districts)
    dist_level_cols <- c("comp_polsby", "comp_edge", "comp_bbox_reock",
        "ndshare", "e_dvs", "minority_vap_share")
    dist_level_cols <- intersect(dist_level_cols, names(combined_data))

    combined_data |>
        dplyr::group_by(.data$state, .data$year, .data$type,
            .data$preclearance_status, .data$draw) |>
        dplyr::summarize(
            n_districts = dplyr::n(),
            dplyr::across(dplyr::all_of(plan_level_cols), ~ .x[1]),
            dplyr::across(dplyr::all_of(dist_level_cols), list(
                mean = ~ mean(.x, na.rm = TRUE),
                median = ~ median(.x, na.rm = TRUE)
            )),
            .groups = "drop"
        )
}

#' Compute distribution summaries across simulated plans
#'
#' For each state-year-type, computes the mean, median, SD, and
#' quantiles (5th, 25th, 75th, 95th) of each metric across all
#' simulated plans.
#'
#' @param plan_summary output of [create_plan_summary()]
#'
#' @return a tibble with one row per state-year-type
#' @export
create_distribution_summary <- function(plan_summary) {
    # Identify numeric metric columns (exclude metadata and draw)
    meta_cols <- c("state", "year", "type", "preclearance_status", "draw", "n_districts")
    metric_cols <- setdiff(names(plan_summary), meta_cols)
    metric_cols <- metric_cols[vapply(plan_summary[metric_cols], is.numeric, logical(1))]

    # Filter to simulated plans only (exclude enacted plans which are non-numeric draws)
    sim_data <- plan_summary |>
        dplyr::filter(!grepl("[a-zA-Z]", .data$draw))

    sim_data |>
        dplyr::group_by(.data$state, .data$year, .data$type, .data$preclearance_status) |>
        dplyr::summarize(
            n_sims = dplyr::n(),
            n_districts = .data$n_districts[1],
            dplyr::across(dplyr::all_of(metric_cols), list(
                mean = ~ mean(.x, na.rm = TRUE),
                median = ~ median(.x, na.rm = TRUE),
                sd = ~ stats::sd(.x, na.rm = TRUE),
                q05 = ~ stats::quantile(.x, 0.05, na.rm = TRUE),
                q25 = ~ stats::quantile(.x, 0.25, na.rm = TRUE),
                q75 = ~ stats::quantile(.x, 0.75, na.rm = TRUE),
                q95 = ~ stats::quantile(.x, 0.95, na.rm = TRUE)
            )),
            .groups = "drop"
        )
}
