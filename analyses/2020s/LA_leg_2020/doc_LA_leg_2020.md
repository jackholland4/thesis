# 2020 Louisiana Legislative Redistricting

## State Senate Districts
- 40 districts
- VRA constraints ported from LA_cd_2020 (minority VAP hinges at 0.46/0.55/0.60)
- Uses minority VAP (vap - vap_white) rather than Black VAP alone

## Workflow
```
01_prep_LA_leg_2020.R  -> data-out/LA_2020/shp_vtd.rds
02_setup_LA_leg_2020.R -> data-out/LA_2020/LA_leg_2020_map_ssd.rds
03_sim_LA_ssd_2020.R   -> data-out/LA_2020/LA_ssd_2020_plans.rds
```
