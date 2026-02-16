# Running State House Redistricting Simulations on the Cluster

This document explains how to run the VRA-unconstrained state house (SHD) redistricting simulations for all available states across the 2000s, 2010s, and 2020s redistricting cycles.

## Overview

We simulate alternative redistricting plans for state house districts using Sequential Monte Carlo (SMC) via the `redist` R package. All VRA-related constraints have been removed — simulations enforce only population equality, contiguity, and compactness. This produces a race-blind baseline for comparing against enacted plans that were drawn under VRA constraints.

**Scale:** 131 state-decade analyses (37 states for 2000, 49 states for 2010, 45 states for 2020), each producing ~10,000 simulated plans.

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

### Required data (already in the repo)

- `census_sldl_2000/` — SLDL boundary shapefiles for 38 states (2000 redistricting cycle)
- `census_sldl_2010/` — SLDL boundary shapefiles for 50 states (2010 redistricting cycle)
- `census_sldl_2022/` — SLDL boundary shapefiles for 50 states (2020 redistricting cycle)

## Step-by-Step Instructions

### 1. Clone the repository

```bash
git clone https://github.com/jackholland4/thesis.git fifty-states
cd fifty-states
```

### 2. Generate all analysis folders

This creates 131 analysis directories, each containing three R scripts (prep, setup, simulate), and unzips the SLDL shapefiles to the correct locations.

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

This submits a Slurm array job with 131 tasks. Each task runs one state-decade analysis end-to-end (~2–12 hours depending on state size).

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
| **2000s** | 37/49 | 11 states (AR, CA, FL, HI, KY, MD, ME, MN, MT, NH, TX) lack SLDL shapefiles on Census TIGER/Line; AK lacks VTD data |
| **2010s** | 49/49 | Complete coverage |
| **2020s** | 45/49 | CA, HI, ME, OR lack VTD data from the ALARM Project |
| **Total** | **131** | NE excluded from all decades (unicameral legislature) |

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

## Troubleshooting

- **Job runs out of memory:** Increase `--mem` (try 64G or 96G for states with 100+ districts)
- **Job times out:** Increase `--time` (try 24:00:00 or 48:00:00)
- **`download_redistricting_file()` fails:** The cluster may need internet access. Run `01_prep` scripts on a login node first, then submit `02_setup` + `03_sim` as batch jobs.
- **`geo_match()` warnings:** Some VTDs may not overlap cleanly with the SLDL boundaries. Small numbers of NAs are normal; large numbers indicate a CRS mismatch.
- **Simulation doesn't converge:** The `03_sim` scripts use `verbose = TRUE`. Check the log for low acceptance rates. Try increasing `pop_temper` or `mh_accept_per_smc`.
