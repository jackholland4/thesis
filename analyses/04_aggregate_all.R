###############################################################################
# Aggregate all simulation statistics across states and decades
# Produces combined datasets for cross-state, cross-decade regression analysis
###############################################################################

suppressMessages({
    library(dplyr)
    library(readr)
    library(cli)
    library(here)
    devtools::load_all() # load fifty.states utilities
})

# 1. Read all stats CSVs and collapse to plan-level -----
# aggregate_all_stats() collapses each state's district-level CSV to plan-level
# immediately after reading, so only one state is in memory at a time.
# (Loading all ~142 district-level files first would require ~100M rows in memory.)
cli_process_start("Aggregating all simulation statistics")

plan_summary <- aggregate_all_stats(here("data-out"))

cli_process_done()
cli_alert_info("Plan summary: {nrow(plan_summary)} plans across {length(unique(paste(plan_summary$state, plan_summary$year)))} state-year combinations")

# 3. Create distribution summary (one row per state-year) -----
cli_process_start("Computing distribution summaries")

dist_summary <- create_distribution_summary(plan_summary)

cli_process_done()

# 4. Save outputs -----
out_dir <- here("data-out/combined")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

cli_process_start("Saving aggregated outputs to {.path data-out/combined/}")

# all_plans.csv (~500 MB, ~1.4M rows) is skipped — not needed for regression.
# Export it manually if you need plan-level distributions:
#   write_csv(plan_summary, file.path(out_dir, "all_plans.csv"))
write_csv(dist_summary, file.path(out_dir, "distribution_summary.csv"))

cli_process_done()
cli_alert_success("Saved {.file distribution_summary.csv} ({nrow(dist_summary)} rows, {ncol(dist_summary)} columns)")
