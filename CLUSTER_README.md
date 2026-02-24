# Third Cluster Run (Feb 2026)

The diagnostic script (`analyses/diagnose_shd_failures.R`) identified ~65 non-complete state-decade runs after the second run. This section documents the fixes committed and the steps needed before resubmitting.

## What changed

### 1. New: `Download_2013_script.py` — 2010-cycle SLDL shapefiles

The 2010-cycle prep scripts (`01_prep_XX_shd_2010.R`) read TIGER 2013 SLDL shapefiles from `census_sldl_2013/`. There was no script to download these files. `Download_2013_script.py` now fills this gap.

**Affected states (prep_failed due to missing shapefile):** WA, WI, WV, WY (2010), and any other states whose `census_sldl_2013/` entry was absent.

### 2. Block-data prep for pop-too-large states (2010 and 2020 cycles)

The batch generator now automatically selects block-level prep for states where VTDs exceed per-district population targets. The threshold is any state that appeared as `pop_too_large` in the diagnosis.

| Cycle | Block-data states |
|-------|------------------|
| 2020  | MT, ND, NH, VT, WY |
| 2010  | AL, ME, MT, ND, NH, VT, WY |

For these state-decade pairs, `01_prep_*.R` now calls `build_block_data()` (which builds Census block demographics + VTD election crosswalk) and `join_block_shapefile()` instead of the VTD equivalents. The enacted plan is still assigned via `geo_match()` against the SLDL shapefile (2010 cycle) or `leg_from_baf(..., to = "block")` (2020 cycle).

The output file is `shp_block.rds` instead of `shp_vtd.rds`. The diagnostic script now checks for both.

**New utility functions in `R/utils.R`:**
- `join_block_shapefile(year = 2010)` — now supported (previously 2020 only)
- `build_block_data(year = 2010)` — now supported (previously 2020 only); uses `censable::build_dec(year=2010)` + `get_baf_10()` crosswalk

### 3. NA imputation for enacted district column (`fill_na_enacted()`)

`geo_match()` returns `NA` for VTDs near state borders that don't overlap cleanly with any SLDL district polygon. When any `shd_YEAR` values are NA, `redist_map()` treats the NA-assigned VTDs as an extra district, causing the setup to produce e.g. 152 instead of 151 districts (Connecticut, Massachusetts).

A new utility `fill_na_enacted(data, col)` propagates non-NA values from adjacent VTDs using adjacency-based mode iteration. It is now called in every generated prep script immediately after `redist.adjacency()`.

**Affected states:** CT (all decades), MA (2000, 2010), and any state with low-level `geo_match` misses.

### 4. Robust 2010 VTD county download (Fix #5 partial)

The 2010 path in `join_vtd_shapefile()` downloads a VTD ZIP file per county from Census TIGER. Certain counties in KY, MT, and OK lack VTD files and previously caused a hard failure for the entire state. Each county download is now wrapped in `tryCatch()` — a 404 logs a warning and skips the county rather than aborting.

---

## Steps before resubmitting

### Step 1 — Pull and download missing SLDL shapefiles

```bash
git pull origin main

# Download TIGER 2013 SLDL files for all states (needed for 2010-cycle)
python3 Download_2013_script.py
# Output: census_sldl_2013/{STATE}_Leg_2013.zip for each state

# If census_sldl_2010/ or census_sldl_2022/ are also incomplete, re-run:
# python3 Download_2010_script.py   # 2000-cycle shapefiles
# python3 Download_2020_script.py   # 2020-cycle shapefiles
```

### Step 2 — Regenerate all analysis scripts

This overwrites every `01_prep_*.R`, `02_setup_*.R`, and `03_sim_*.R` in the analyses directories and unzips newly downloaded SLDL shapefiles to `data-raw/{STATE}/sldl_{YEAR}/`.

```bash
Rscript -e "setwd('$(pwd)'); source('analyses/00_generate_shd_analyses.R')"
```

> **Cache note:** The `shp_vtd.rds` / `shp_block.rds` files in `data-out/` are protected by an `if (!file.exists(...))` guard. States that already completed prep successfully will skip the rebuild. Only states with missing or corrupt cache files will re-run prep.

### Step 3 — Delete caches for states that need a clean rebuild

States where prep ran but produced a bad result (100% NA enacted, duplicate GEOIDs, or wrong row count) need their cache deleted so prep reruns with the fixed code:

```bash
# CT and MA: shp_vtd.rds cached before fill_na_enacted fix
rm -f data-out/CT_2000/shp_vtd.rds data-out/CT_2010/shp_vtd.rds data-out/CT_2020/shp_vtd.rds
rm -f data-out/MA_2000/shp_vtd.rds data-out/MA_2010/shp_vtd.rds

# MN: 100% NA enacted column in all decades
rm -f data-out/MN_2000/shp_vtd.rds data-out/MN_2010/shp_vtd.rds data-out/MN_2020/shp_vtd.rds

# Block-data states whose shp_vtd.rds was cached from the old VTD prep
# (block prep now writes shp_block.rds to a different path, so no conflict —
#  but delete shp_vtd.rds so setup doesn't pick up stale VTD data)
for st in MT ND NH VT WY; do
  rm -f data-out/${st}_2020/shp_vtd.rds
  rm -f data-out/${st}_2010/shp_vtd.rds
done
rm -f data-out/AL_2010/shp_vtd.rds data-out/ME_2010/shp_vtd.rds
```

### Step 4 — Run prep interactively for block-data states

`build_block_data()` calls `censable::build_dec()` and `tigris::blocks()`, which make Census API requests. Run these on a login node (not a compute node).

**Census API key required.** If you haven't set one up on the cluster:

1. Generate a free key at <https://api.census.gov/data/key_signup.html> (instant, no approval).
2. Add it to your R environment file on the cluster:
   ```bash
   echo 'CENSUS_API_KEY=your_key_here' >> ~/.Renviron
   ```
3. Verify it is visible to R:
   ```bash
   Rscript -e "Sys.getenv('CENSUS_API_KEY')"
   ```
   You should see your key printed, not an empty string. If it is empty, log out and back in so the new `.Renviron` is sourced.

```bash
# On login node — block-data states, 2020 cycle
for st in MT ND NH VT WY; do
  Rscript -e "setwd('$(pwd)'); source('analyses/2020s/${st}_shd_2020/01_prep_${st}_shd_2020.R')"
done

# On login node — block-data states, 2010 cycle
for st in AL ME MT ND NH VT WY; do
  Rscript -e "setwd('$(pwd)'); source('analyses/2010s/${st}_shd_2010/01_prep_${st}_shd_2010.R')"
done
```

After `shp_block.rds` is written for each state, `02_setup` and `03_sim` can be submitted as normal batch jobs.

### Step 5 — Resubmit failed jobs

Use the diagnostic CSV to identify which state-decade pairs still lack a `_stats.csv`:

```bash
# Regenerate the diagnosis CSV
Rscript -e "setwd('$(pwd)'); source('analyses/diagnose_shd_failures.R')"

# Count remaining failures
awk -F',' 'NR>1 && $4 != "complete" {print $1, $2, $4, $5}' \
    data-out/combined/shd_diagnosis.csv | sort -k3
```

Resubmit the corresponding array task indices. The `run_all_shd.sh` scripts already include the full state list in order — match state names to task indices:

```bash
# Example: states at 1-based positions in the decade list
sbatch --array=12,23,47 analyses/run_shd_2020s.sh
sbatch --array=5,18,32,45 analyses/run_shd_2010s.sh
```

---

## Remaining known issues (not yet fixed)

| State(s) | Cycle | Cause | Status |
|----------|-------|-------|--------|
| MN (all) | 2000, 2010, 2020 | `geo_match()` returns 100% NA enacted; root cause unclear | Needs R debugging session on cluster |
| GA, RI | 2020 | Setup succeeded but SMC fails; no log available locally | Inspect SLURM `.err` logs |
| CT, MA | 2000 (if cache not deleted) | NA-enacted extra district | Fixed by cache delete + regenerate |
| OK | 2010 | Census 2010 VTD ZIP extraction failure (Haskell County) | Partially mitigated by `tryCatch`; check if county is now skipped gracefully |
| OK | 2020 | `redistmetrics::part_egap()` error in stats | Package version issue; upgrade `redistmetrics` on cluster |
| CA | 2000 | Memory — 7,049 VTDs × 80 districts | Request 128G+ node or skip |
