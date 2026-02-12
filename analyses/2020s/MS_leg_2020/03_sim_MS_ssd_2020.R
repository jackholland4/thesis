###############################################################################
# Simulate plans for `MS_ssd_2020` SSD
# © ALARM Project, February 2026
###############################################################################

# Run the simulation -----
cli_process_start("Running simulations for {.pkg MS_ssd_2020}")

# VRA constraints (ported from MS_cd_2020)
constr <- redist_constr(map_ssd) |>
    add_constr_grp_hinge(20, vap_black, vap, tgts_group = c(0.55)) |>
    add_constr_grp_hinge(-20, vap_black, vap, tgts_group = 0.4) |>
    add_constr_grp_hinge(-5, vap_black, vap, tgts_group = 0.2)

set.seed(2020)

plans <- redist_smc(map_ssd, nsims = 2500, runs = 2L,
    counties = pseudo_county, constraints = constr)

plans <- plans |>
    group_by(chain) |>
    filter(as.integer(draw) < min(as.integer(draw)) + 2500) |> # thin samples
    ungroup()
plans <- match_numbers(plans, "ssd_2020")

cli_process_done()
cli_process_start("Saving {.cls redist_plans} object")

# Output the redist_map object. Do not edit this path.
write_rds(plans, here("data-out/MS_2020/MS_ssd_2020_plans.rds"), compress = "xz")
cli_process_done()

# Compute summary statistics -----
cli_process_start("Computing summary statistics for {.pkg MS_ssd_2020}")

plans <- add_summary_stats(plans, map_ssd)

# Output the summary statistics. Do not edit this path.
save_summary_stats(plans, "data-out/MS_2020/MS_ssd_2020_stats.csv")

cli_process_done()

if (interactive()) {
    library(ggplot2)
    library(patchwork)

    validate_analysis(plans, map_ssd)
    summary(plans)
}
