###############################################################################
# Simulate plans for `NC_cd_2010`
# © ALARM Project, April 2022
###############################################################################

# Run the simulation -----
cli_process_start("Running simulations for {.pkg NC_cd_2010}")

set.seed(2010)

plans <- redist_smc(map, nsims = 12e3,
    runs = 2L,
    ncores = 2L,
    counties = county,
    pop_temper = 0.05)

plans <- match_numbers(plans, "cd_2010")

plans <- plans %>%
    group_by(chain) %>%
    slice(1:(2500*attr(map, "ndists"))) %>% # thin samples
    ungroup()

cli_process_done()
cli_process_start("Saving {.cls redist_plans} object")

# Output the redist_map object. Do not edit this path.
write_rds(plans, here("data-out/NC_2010/NC_cd_2010_plans.rds"), compress = "xz")
cli_process_done()

# Compute summary statistics -----
cli_process_start("Computing summary statistics for {.pkg NC_cd_2010}")

plans <- add_summary_stats(plans, map)

# Output the summary statistics. Do not edit this path.
save_summary_stats(plans, "data-out/NC_2010/NC_cd_2010_stats.csv")

cli_process_done()
