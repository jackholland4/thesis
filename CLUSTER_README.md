# Running State House Redistricting Simulations on the Cluster

This document explains how to run the VRA-unconstrained state house (SHD) redistricting simulations for all available states across the 2000s, 2010s, and 2020s redistricting cycles.

## Overview

We simulate alternative redistricting plans for state house districts using Sequential Monte Carlo (SMC) via the `redist` R package. All VRA-related constraints have been removed — simulations enforce only population equality, contiguity, and compactness. This produces a race-blind baseline for comparing against enacted plans that were drawn under VRA constraints.

**Scale:** 142 state-decade analyses (48 states for 2000, 49 states for 2010, 45 states for 2020), each producing ~10,000 simulated plans.

## Prerequisites

### R packages (install once on the cluster)

```r
install.packages(c("redist", "redistmetrics", "geomander", "sf", "dplyr",
                    "readr", "stringr", "purrr", "tidyr", "cli", "here",
                    "censable", "PL94171", "dataverse", "rmapshaper",
                    "devtools", "ggplot2", "patchwork", "cvap", "tinytiger"))
```

For 2000s analyses, also install:
```r
install.packages("baf")
```

### Required data (downloaded separately, not in git)

Each decade's analysis uses SLDL boundary shapefiles from a specific TIGER/Line vintage to get the **post-census enacted plans** (not the pre-census boundaries):

| Decade | TIGER Vintage | Directory | Column | Rationale |
|--------|--------------|-----------|--------|-----------|
| **2000s** | TIGER 2010 (`sldl10`) | `census_sldl_2010/` | `SLDLST10` | `sldl10` = districts in effect for the 2010 Census = post-2000 enacted plans |
| **2010s** | TIGER 2013 (`sldl`) | `census_sldl_2013/` | `SLDLST` | First vintage where LSY jumps to 2013 = post-2010 enacted plans |
| **2020s** | TIGER 2022 (`sldl`) | `census_sldl_2022/` | `SLDLST` | Post-2020 enacted plans |

- `census_sldl_2010/` — SLDL boundary shapefiles for 50 states (post-2000 enacted plans)
- `census_sldl_2013/` — SLDL boundary shapefiles for 49 states (post-2010 enacted plans)
- `census_sldl_2022/` — SLDL boundary shapefiles for 50 states (post-2020 enacted plans)

## Step-by-Step Instructions

### 1. Clone the repository

```bash
git clone https://github.com/jackholland4/thesis.git fifty-states
cd fifty-states
```

### 2. Generate all analysis folders

This creates 142 analysis directories, each containing three R scripts (prep, setup, simulate), and unzips the SLDL shapefiles to the correct locations.

```bash
Rscript -e "setwd('$(pwd)'); source('analyses/00_generate_shd_analyses.R')"
```

This will create folders like:
```
analyses/2000s/GA_shd_2000/
    01_prep_GA_shd_2000.R    # Downloads VTD data, builds shapefile
    02_setup_GA_shd_2000.R   # Creates redist_map object
    03_sim_GA_shd_2000.R     # Runs SMC simulation, computes statistics

analyses/2010s/GA_shd_2010/
    01_prep_GA_shd_2010.R
    02_setup_GA_shd_2010.R
    03_sim_GA_shd_2010.R

analyses/2020s/GA_shd_2020/
    01_prep_GA_shd_2020.R
    02_setup_GA_shd_2020.R
    03_sim_GA_shd_2020.R
```

### 3. Submit to the cluster

```bash
mkdir -p logs
sbatch analyses/run_all_shd.sh
```

This submits a Slurm array job with 142 tasks. Each task runs one state-decade analysis end-to-end (~2–12 hours depending on state size).

**Default resources per task:** 32 GB memory, 4 CPUs, 12-hour walltime.

For large states (CA, TX, NY, PA with 100–150+ districts), you may want to increase memory:

```bash
# Run only the large states with more resources (check array indices in run_all_shd.sh)
sbatch --mem=64G --time=24:00:00 --array=42,49,69,73 analyses/run_all_shd.sh
```

### 4. Monitor progress

```bash
# Check job status
squeue -u $USER

# Check a specific job's output
tail -f logs/shd_<JOBID>_<TASKID>.out

# Count completed analyses
ls data-out/*/\*_shd_*_stats.csv 2>/dev/null | wc -l
```

### 5. Aggregate results (after all jobs complete)

```bash
Rscript -e "setwd('$(pwd)'); source('analyses/04_aggregate_all.R')"
```

This produces two files in `data-out/combined/`:

| File | Description |
|------|-------------|
| `all_plans.csv` | One row per simulated plan per state-year. Contains all plan-level metrics (partisan bias, efficiency gap, mean-median difference, competitive districts, majority-minority counts, compactness, etc.) plus `state`, `year`, `preclearance_status` columns ready for regression. |
| `distribution_summary.csv` | One row per state-year. Contains mean, median, SD, and quantiles (5th, 25th, 75th, 95th) for every metric across all simulated plans. |

## Data Coverage

| Decade | States | Notes |
|--------|--------|-------|
| **2000s** | 48/49 | AK lacks VTD data; uses TIGER 2010 `sldl10` shapefiles (post-2000 plans) |
| **2010s** | 49/49 | Complete coverage; uses TIGER 2013 shapefiles (post-2010 plans) |
| **2020s** | 45/49 | CA, HI, ME, OR lack VTD data; uses TIGER 2022 shapefiles (post-2020 plans) |
| **Total** | **142** | NE excluded from all decades (unicameral legislature) |

## Output Metrics

Each simulation produces a `*_stats.csv` file containing district-level and plan-level metrics:

**Partisan:** efficiency gap (`egap`), partisan bias (`pbias`), mean-median difference (`mean_median_diff`), seats-votes responsiveness (`responsiveness`), competitive district count (`n_competitive`), expected Democratic seats (`e_dem`)

**Racial:** minority VAP share per district (`minority_vap_share`), majority-minority districts >50% (`n_majority_minority`), opportunity districts 40–50% (`n_opportunity`), influence districts 30–40% (`n_influence`), average minority VAP (`avg_minority_vap`)

**Geometric:** Polsby-Popper per district (`comp_polsby`), plan mean (`mean_polsby`), plan SD (`sd_polsby`), fraction of edges kept (`comp_edge`)

## Pipeline Architecture

Each state-decade analysis runs three scripts in order:

1. **01_prep** — Downloads VTD-level census data (demographics + election results) from the ALARM Project's census-2020 repository, joins with TIGER shapefile geometry, and uses `geo_match()` to assign each VTD to its enacted state house district using the SLDL boundary shapefiles.

2. **02_setup** — Builds a `redist_map` object with 5% population tolerance, creates pseudo-counties for the county-split constraint, and saves the map to `data-out/`.

3. **03_sim** — Runs the SMC sampler (`redist_smc()`) with 2,000 plans across 5 independent chains, thins to 10,000 total plans, computes all summary statistics, and saves the results to `data-out/`.

---

## Second Cluster Run (Feb 2026)

The first run surfaced four recurring error categories. All four have been patched in commits `760a98b`, `0c60d5c`, and `4f48c4a`. Follow the steps below before resubmitting.

### Step 1 — Pull the latest changes

```bash
git pull origin main
```

### Step 2 — Re-run the analysis generator

The batch generator (`00_generate_shd_analyses.R`) was updated to add `suggest_neighbors()` to every prep script, which fixes the contiguous-adjacency errors for island and coastal states. Re-running it overwrites all `01_prep_*.R` scripts in `analyses/2000s/`, `analyses/2010s/`, and `analyses/2020s/`:

```bash
Rscript -e "setwd('$(pwd)'); source('analyses/00_generate_shd_analyses.R')"
```

> **Note:** The `shp_vtd.rds` cache files in `data-out/` are unaffected. If prep already completed successfully for a state, re-running its `01_prep` script will skip the rebuild (the `if (!file.exists(...))` guard is in place).

### Step 3 — Resubmit the failed jobs

Resubmit only the tasks that failed in the first run. If you saved the Slurm job array indices of failed tasks:

```bash
# Example: resubmit tasks 12, 23, 47, 81 from the original array
sbatch --array=12,23,47,81 analyses/run_all_shd.sh
```

If you did not save the indices, identify which states are missing output and rerun those:

```bash
# List states with no stats file yet
comm -23 \
  <(ls analyses/2020s/ | sort) \
  <(ls data-out/*/\*_shd_2020_stats.csv 2>/dev/null | xargs -I{} basename {} _stats.csv | sort)
```

---

### What was fixed (and which states are affected)

#### Adjacency not contiguous — *AK, HI (all decades), FL, NY, RI, KS, CA*

**Cause:** Island or water-separated precincts have no touching neighbor, leaving the graph disconnected. `redist_smc()` requires a fully connected graph.

**Fix:** `suggest_neighbors()` is now called immediately after `redist.adjacency()` in every generated prep script (Step 2 above regenerates these). No manual action needed — just regenerate and rerun.

#### Memory / exploding matrices — *MN, VT (all decades)*

**Cause:** Some TIGER 2010 VTD shapefiles store multi-part geometries as separate rows with the same GEOID. `left_join()` duplicates rows, inflating the dataset from ~4K to 100K+ rows, causing impossibly large adjacency matrix allocation.

**Fix:** `join_vtd_shapefile()` in `R/utils.R` now deduplicates by grouping on GEOID and unioning multi-part geometries before the join. This fix is in the shared package code — no script changes needed. Since these states likely cached a corrupt `shp_vtd.rds`, **delete the bad cache first**:

```bash
rm data-out/MN_2010/shp_vtd.rds data-out/MN_2000/shp_vtd.rds
rm data-out/VT_2010/shp_vtd.rds data-out/VT_2000/shp_vtd.rds
```

Then rerun the corresponding `01_prep` scripts — the fixed `join_vtd_shapefile()` will rebuild them correctly.

#### Alabama "Pop too large" — *AL (2020)*

**Diagnosis:** VTDs are not the problem. The maximum Alabama VTD population is 28,753 against a SHD target of 47,850 — no VTD exceeds the target. The error was caused by the same row-explosion bug as MN/VT above (corrupt geometry join inflating apparent unit populations).

**Fix:** Same as MN/VT — the `join_vtd_shapefile()` dedup fix resolves it. Delete any cached `shp_vtd.rds` and rerun `01_prep`:

```bash
rm -f data-out/AL_2020/shp_vtd.rds
```

#### Pop too large — *NH, ME, MT, ND* (genuine granularity issue)

These states have so many small districts that some VTDs contain more people than an entire district's population target. VTD-level data cannot be used:

| State | Districts | Target pop | Largest VTD | Verdict |
|-------|-----------|-----------|-------------|---------|
| NH    | 400 SHD   | ~3,300    | towns >10K  | blocks required |
| ME    | 151 SHD   | ~8,800    | large towns | blocks required |
| MT    | 100 SHD   | ~10,700   | urban VTDs  | blocks required |
| ND    | 94 SHD    | ~7,700    | urban VTDs  | blocks required |

These four states are **not handled by the batch generator** — they require Census block-level analyses set up separately. The pipeline now supports this. For each state-decade combination that failed, create a block-level analysis folder:

```r
# Run on a login node (not as a batch job) — needs internet for downloads
devtools::load_all(".")

# 2020s
init_analysis("NH", "leg", 2020, blocks = TRUE)
init_analysis("MT", "leg", 2020, blocks = TRUE)
init_analysis("ND", "leg", 2020, blocks = TRUE)
# ME is already excluded from the 2020 batch (no ALARM VTD file exists)
init_analysis("ME", "leg", 2020, blocks = TRUE)

# 2010s (if those decades also failed)
init_analysis("NH", "leg", 2010, blocks = TRUE)
init_analysis("ME", "leg", 2010, blocks = TRUE)
init_analysis("MT", "leg", 2010, blocks = TRUE)
init_analysis("ND", "leg", 2010, blocks = TRUE)
```

Each `init_analysis(..., blocks = TRUE)` creates a folder with a `01_prep_block_*` script that:
1. Tries to download a pre-built ALARM block CSV (available for CA, HI, ME, OR)
2. If not available, builds block demographics from `censable::build_dec()` and disaggregates VTD election data to blocks by population weight
3. Joins Census block geometry via `tigris::blocks()`
4. Uses the PL BAF directly for block-level municipality and enacted-district assignments

Run each block-level analysis interactively on a login node since `censable::build_dec()` and `tigris::blocks()` make Census API requests. After `01_prep_block_*.R` completes and saves `shp_block.rds`, `02_setup_*.R` and `03_sim_*.R` can be submitted as batch jobs normally.

---

---

## Aggregation fixes (Feb 2026, post-second-run)

Two changes were made to `04_aggregate_all.R` and `R/aggregate_stats.R` after the aggregation script crashed during post-run export.

### Memory crash in `aggregate_all_stats()`

**Cause:** Each per-state `_stats.csv` is written at district level — one row per district per plan. A 100-district state with 10,000 plans produces a 1M-row file. The old `aggregate_all_stats()` loaded all 142 of these into one combined tibble (~100M rows, 20–40 GB) before collapsing it to plan level.

**Fix (commit `0ca62f5`):** Each CSV is now collapsed to plan level immediately after reading. Peak memory is bounded by one state's district data at a time. Pull and rerun `04_aggregate_all.R` — no other changes needed.

### Output file size

`all_plans.csv` (one row per simulated plan) is ~500 MB and is **not needed for regression analysis**. Writing it has been disabled by default. The only output is now:

| File | Rows | Contents |
|------|------|----------|
| `distribution_summary.csv` | ~150 | One row per state-decade; mean, median, SD, and quantiles for every metric across all simulated plans — the regression-ready dataset |

To run the aggregation:

```bash
Rscript -e "setwd('$(pwd)'); source('analyses/04_aggregate_all.R')"
```

Then copy `data-out/combined/distribution_summary.csv` off the cluster. It is small enough to transfer without issue.

If you need the plan-level data for a specific analysis, uncomment the `write_csv(plan_summary, ...)` line in `04_aggregate_all.R`.

---

---

## Third Cluster Run (Feb 2026)

The diagnostic script (`analyses/diagnose_shd_failures.R`) identified ~65 non-complete state-decade runs after the second run. This section documents the fixes committed and the steps needed before resubmitting.

### What changed

#### 1. New: `Download_2013_script.py` — 2010-cycle SLDL shapefiles

The 2010-cycle prep scripts (`01_prep_XX_shd_2010.R`) read TIGER 2013 SLDL shapefiles from `census_sldl_2013/`. There was no script to download these files. `Download_2013_script.py` now fills this gap.

**Affected states (prep_failed due to missing shapefile):** WA, WI, WV, WY (2010), and any other states whose `census_sldl_2013/` entry was absent.

#### 2. Block-data prep for pop-too-large states (2010 and 2020 cycles)

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

#### 3. NA imputation for enacted district column (`fill_na_enacted()`)

`geo_match()` returns `NA` for VTDs near state borders that don't overlap cleanly with any SLDL district polygon. When any `shd_YEAR` values are NA, `redist_map()` treats the NA-assigned VTDs as an extra district, causing the setup to produce e.g. 152 instead of 151 districts (Connecticut, Massachusetts).

A new utility `fill_na_enacted(data, col)` propagates non-NA values from adjacent VTDs using adjacency-based mode iteration. It is now called in every generated prep script immediately after `redist.adjacency()`.

**Affected states:** CT (all decades), MA (2000, 2010), and any state with low-level `geo_match` misses.

#### 4. Robust 2010 VTD county download (Fix #5 partial)

The 2010 path in `join_vtd_shapefile()` downloads a VTD ZIP file per county from Census TIGER. Certain counties in KY, MT, and OK lack VTD files and previously caused a hard failure for the entire state. Each county download is now wrapped in `tryCatch()` — a 404 logs a warning and skips the county rather than aborting.

---

### Steps before resubmitting

#### Step 1 — Pull and download missing SLDL shapefiles

```bash
git pull origin main

# Download TIGER 2013 SLDL files for all states (needed for 2010-cycle)
python3 Download_2013_script.py
# Output: census_sldl_2013/{STATE}_Leg_2013.zip for each state

# If census_sldl_2010/ or census_sldl_2022/ are also incomplete, re-run:
# python3 Download_2010_script.py   # 2000-cycle shapefiles
# python3 Download_2020_script.py   # 2020-cycle shapefiles
```

#### Step 2 — Regenerate all analysis scripts

This overwrites every `01_prep_*.R`, `02_setup_*.R`, and `03_sim_*.R` in the analyses directories and unzips newly downloaded SLDL shapefiles to `data-raw/{STATE}/sldl_{YEAR}/`.

```bash
Rscript -e "setwd('$(pwd)'); source('analyses/00_generate_shd_analyses.R')"
```

> **Cache note:** The `shp_vtd.rds` / `shp_block.rds` files in `data-out/` are protected by an `if (!file.exists(...))` guard. States that already completed prep successfully will skip the rebuild. Only states with missing or corrupt cache files will re-run prep.

#### Step 3 — Delete caches for states that need a clean rebuild

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

#### Step 4 — Run prep interactively for block-data states

`build_block_data()` calls `censable::build_dec()` and `tigris::blocks()`, which make Census API requests. Run these on a login node (not a compute node):

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

#### Step 5 — Resubmit failed jobs

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

### Remaining known issues (not yet fixed)

| State(s) | Cycle | Cause | Status |
|----------|-------|-------|--------|
| MN (all) | 2000, 2010, 2020 | `geo_match()` returns 100% NA enacted; root cause unclear | Needs R debugging session on cluster |
| GA, RI | 2020 | Setup succeeded but SMC fails; no log available locally | Inspect SLURM `.err` logs |
| CT, MA | 2000 (if cache not deleted) | NA-enacted extra district | Fixed by cache delete + regenerate |
| OK | 2010 | Census 2010 VTD ZIP extraction failure (Haskell County) | Partially mitigated by `tryCatch`; check if county is now skipped gracefully |
| OK | 2020 | `redistmetrics::part_egap()` error in stats | Package version issue; upgrade `redistmetrics` on cluster |
| CA | 2000 | Memory — 7,049 VTDs × 80 districts | Request 128G+ node or skip |

---

## Troubleshooting

- **Job runs out of memory:** Increase `--mem` (try 64G or 96G for states with 100+ districts)
- **Job times out:** Increase `--time` (try 24:00:00 or 48:00:00)
- **`download_redistricting_file()` fails:** The cluster may need internet access. Run `01_prep` scripts on a login node first, then submit `02_setup` + `03_sim` as batch jobs.
- **`geo_match()` warnings:** Some VTDs may not overlap cleanly with the SLDL boundaries. Small numbers of NAs are normal; large numbers indicate a CRS mismatch.
- **Simulation doesn't converge:** The `03_sim` scripts use `verbose = TRUE`. Check the log for low acceptance rates. Try increasing `pop_temper` or `mh_accept_per_smc`.
