###############################################################################
# Simulate plans for `TX_ssd_2020` SSD
# © ALARM Project, February 2026
###############################################################################

# Run the simulation -----
cli_process_start("Running simulations for {.pkg TX_ssd_2020}")

# VRA constraints (ported from TX_cd_2020 full-state recombination phase)
constr <- redist_constr(map_ssd) |>
    # Hispanic VAP
    add_constr_grp_hinge(3, vap_hisp, total_pop = vap, tgts_group = c(0.45)) |>
    add_constr_grp_hinge(-3, vap_hisp, vap, 0.35) |>
    add_constr_grp_inv_hinge(3, vap_hisp, vap, 0.70) |>
    # Black VAP
    add_constr_grp_hinge(3, vap_black, total_pop = vap, tgts_group = c(0.45)) |>
    add_constr_grp_hinge(-3, vap_black, vap, 0.35) |>
    add_constr_grp_inv_hinge(3, vap_black, vap, 0.70)

set.seed(2020)

plans <- redist_smc(map_ssd, nsims = 5e3, runs = 2L,
    counties = pseudo_county, constraints = constr, pop_temper = 0.03)

plans <- plans |>
    group_by(chain) |>
    filter(as.integer(draw) < min(as.integer(draw)) + 2500) |> # thin samples
    ungroup()
plans <- match_numbers(plans, "ssd_2020")

cli_process_done()
cli_process_start("Saving {.cls redist_plans} object")

# Output the redist_map object. Do not edit this path.
write_rds(plans, here("data-out/TX_2020/TX_ssd_2020_plans.rds"), compress = "xz")
cli_process_done()

# Compute summary statistics -----
cli_process_start("Computing summary statistics for {.pkg TX_ssd_2020}")

plans <- add_summary_stats(plans, map_ssd)

# Output the summary statistics. Do not edit this path.
save_summary_stats(plans, "data-out/TX_2020/TX_ssd_2020_stats.csv")

cli_process_done()

if (interactive()) {
    library(ggplot2)
    library(patchwork)

    validate_analysis(plans, map_ssd)
    summary(plans)
}
