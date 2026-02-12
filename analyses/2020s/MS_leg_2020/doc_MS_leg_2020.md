# 2020 Mississippi Legislative Redistricting

## State Senate Districts
- 52 districts
- VRA constraints ported from MS_cd_2020 (Black VAP hinges at 0.20/0.40/0.55)

## Workflow
```
01_prep_MS_leg_2020.R  -> data-out/MS_2020/shp_vtd.rds
02_setup_MS_leg_2020.R -> data-out/MS_2020/MS_leg_2020_map_ssd.rds
03_sim_MS_ssd_2020.R   -> data-out/MS_2020/MS_ssd_2020_plans.rds
```
