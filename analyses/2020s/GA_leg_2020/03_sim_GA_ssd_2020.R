###############################################################################
# Simulate plans for `GA_ssd_2020` SSD
# © ALARM Project, February 2026
###############################################################################

# Run the simulation -----
cli_process_start("Running simulations for {.pkg GA_ssd_2020}")

# VRA constraints (ported from GA_cd_2020)
constr <- redist_constr(map_ssd) |>
    add_constr_grp_hinge(20, vap_black, vap, 0.52) |>
    add_constr_grp_hinge(-20, vap_black, vap, 0.45) |>
    add_constr_grp_inv_hinge(10, vap_black, vap, 0.62)

set.seed(2020)

plans <- redist_smc(map_ssd, nsims = 1e4, runs = 2L,
    counties = pseudo_county, constraints = constr, pop_temper = 0.01)

plans <- plans |>
    group_by(chain) |>
    filter(as.integer(draw) < min(as.integer(draw)) + 2500) |> # thin samples
    ungroup()
plans <- match_numbers(plans, "ssd_2020")

cli_process_done()
cli_process_start("Saving {.cls redist_plans} object")

# Output the redist_map object. Do not edit this path.
write_rds(plans, here("data-out/GA_2020/GA_ssd_2020_plans.rds"), compress = "xz")
cli_process_done()

# Compute summary statistics -----
cli_process_start("Computing summary statistics for {.pkg GA_ssd_2020}")

plans <- add_summary_stats(plans, map_ssd)

# Output the summary statistics. Do not edit this path.
save_summary_stats(plans, "data-out/GA_2020/GA_ssd_2020_stats.csv")

cli_process_done()

if (interactive()) {
    library(ggplot2)
    library(patchwork)

    validate_analysis(plans, map_ssd)
    summary(plans)
}
