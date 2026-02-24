###############################################################################
# Simulate plans for `OR_shd_2010` SHD
###############################################################################

# Run the simulation -----
cli_process_start("Running simulations for {.pkg OR_shd_2010}")

set.seed(2010)

plans <- redist_smc(
    map_shd,
    nsims = 2e3, runs = 5,
    counties = pseudo_county,
    verbose = TRUE
)

plans <- plans |>
    group_by(chain) |>
    filter(as.integer(draw) < min(as.integer(draw)) + 2000) |> # thin samples
    ungroup()
plans <- match_numbers(plans, "shd_2010")

cli_process_done()
cli_process_start("Saving {.cls redist_plans} object")

# Output the redist_plans object
write_rds(plans, here("data-out/OR_2010/OR_shd_2010_plans.rds"), compress = "xz")
cli_process_done()

# Compute summary statistics -----
cli_process_start("Computing summary statistics for {.pkg OR_shd_2010}")

plans <- add_summary_stats(plans, map_shd)

# Output the summary statistics
save_summary_stats(plans, "data-out/OR_2010/OR_shd_2010_stats.csv")

cli_process_done()
