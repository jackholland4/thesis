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

## Troubleshooting

- **Job runs out of memory:** Increase `--mem` (try 64G or 96G for states with 100+ districts)
- **Job times out:** Increase `--time` (try 24:00:00 or 48:00:00)
- **`download_redistricting_file()` fails:** The cluster may need internet access. Run `01_prep` scripts on a login node first, then submit `02_setup` + `03_sim` as batch jobs.
- **`geo_match()` warnings:** Some VTDs may not overlap cleanly with the SLDL boundaries. Small numbers of NAs are normal; large numbers indicate a CRS mismatch.
- **Simulation doesn't converge:** The `03_sim` scripts use `verbose = TRUE`. Check the log for low acceptance rates. Try increasing `pop_temper` or `mh_accept_per_smc`.
