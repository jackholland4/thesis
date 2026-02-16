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

# 1. Read and combine all stats CSVs -----
cli_process_start("Aggregating all simulation statistics")

combined <- aggregate_all_stats(here("data-out"))

cli_process_done()
cli_alert_info("Combined dataset: {nrow(combined)} rows across {length(unique(paste(combined$state, combined$year)))} state-year combinations")

# 2. Create plan-level summary (one row per simulated plan) -----
cli_process_start("Creating plan-level summary")

plan_summary <- create_plan_summary(combined)

cli_process_done()
cli_alert_info("Plan summary: {nrow(plan_summary)} plans")

# 3. Create distribution summary (one row per state-year) -----
cli_process_start("Computing distribution summaries")

dist_summary <- create_distribution_summary(plan_summary)

cli_process_done()

# 4. Save outputs -----
out_dir <- here("data-out/combined")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

cli_process_start("Saving aggregated outputs to {.path data-out/combined/}")

write_csv(plan_summary, file.path(out_dir, "all_plans.csv"))
write_csv(dist_summary, file.path(out_dir, "distribution_summary.csv"))

cli_process_done()
cli_alert_success("Saved {.file all_plans.csv} ({nrow(plan_summary)} rows)")
cli_alert_success("Saved {.file distribution_summary.csv} ({nrow(dist_summary)} rows)")
