# 2020 Alabama Legislative Redistricting

## State Senate Districts
- 35 districts
- VRA constraints ported from AL_cd_2020 (Black VAP hinges at 0.30/0.42/0.45)

## Workflow
```
01_prep_AL_leg_2020.R  -> data-out/AL_2020/shp_vtd.rds
02_setup_AL_leg_2020.R -> data-out/AL_2020/AL_leg_2020_map_ssd.rds
03_sim_AL_ssd_2020.R   -> data-out/AL_2020/AL_ssd_2020_plans.rds
```
