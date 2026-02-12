# 2020 North Carolina Legislative Redistricting

## State Senate Districts
- 50 districts
- VRA constraints ported from NC_cd_2020 (Black VAP hinges at 0.30/0.33/0.37)
- compactness = 1, pop_temper = 0.01

## Workflow
```
01_prep_NC_leg_2020.R  -> data-out/NC_2020/shp_vtd.rds
02_setup_NC_leg_2020.R -> data-out/NC_2020/NC_leg_2020_map_ssd.rds
03_sim_NC_ssd_2020.R   -> data-out/NC_2020/NC_ssd_2020_plans.rds
```
