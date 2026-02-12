# 2020 Georgia Legislative Redistricting

## State Senate Districts
- 56 districts
- VRA constraints ported from GA_cd_2020 (Black VAP hinges at 0.45/0.52/0.62)
- pop_temper = 0.01 (for many districts / tighter tolerance)

## Workflow
```
01_prep_GA_leg_2020.R  -> data-out/GA_2020/shp_vtd.rds
02_setup_GA_leg_2020.R -> data-out/GA_2020/GA_leg_2020_map_ssd.rds
03_sim_GA_ssd_2020.R   -> data-out/GA_2020/GA_ssd_2020_plans.rds
```
