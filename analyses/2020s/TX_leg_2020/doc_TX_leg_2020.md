# 2020 Texas Legislative Redistricting

## State Senate Districts
- 31 districts
- VRA constraints ported from TX_cd_2020 full-state phase (Hispanic + Black CVAP)
- Simplified from clustered CD approach to single-pass SSD simulation
- pop_temper = 0.03

## Workflow
```
01_prep_TX_leg_2020.R  -> data-out/TX_2020/shp_vtd.rds
02_setup_TX_leg_2020.R -> data-out/TX_2020/TX_leg_2020_map_ssd.rds
03_sim_TX_ssd_2020.R   -> data-out/TX_2020/TX_ssd_2020_plans.rds
```
