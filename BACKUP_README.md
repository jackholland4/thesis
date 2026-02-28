# SHD Backup Simulation — VTD-Only Run

This document describes how to run the state house (SHD) redistricting simulations
on the cluster using the **VTD-only backup pipeline**. This run excludes a small set
of states that require Census block-level data due to known data pipeline issues.
All other steps — simulation parameters, output formats, and summary statistics — are
identical to the main pipeline.

---

## What Is This Backup?

The main pipeline (`00_generate_shd_analyses.R`) routes seven state-decade combinations
through a Census block-level data path (`build_block_data()`) because their VTDs are too
large relative to their district population targets. That path has intermittent column
naming issues that can cause prep to fail. This backup simply skips those states and runs
everything else through the standard VTD pipeline, which is fully stable.

The backup generator is: `analyses/00_generate_shd_analyses_vtd_only.R`
The backup SLURM script is: `analyses/run_shd_vtd_only.sh`

---

## Analyses Included

**130 state-decade analyses across three redistricting cycles.**

### 2000 cycle — 48 states (all VTD-based, no exclusions)

| | | | | | | | |
|--|--|--|--|--|--|--|--|
| AL | AR | AZ | CA | CO | CT | DE | FL |
| GA | HI | IA | ID | IL | IN | KS | KY |
| LA | MA | MD | ME | MI | MN | MO | MS |
| MT | NC | ND | NH | NJ | NM | NV | NY |
| OH | OK | OR | PA | RI | SC | SD | TN |
| TX | UT | VA | VT | WA | WI | WV | WY |

*(AK and NE excluded from all cycles: AK lacks 2000 VTD data; NE has a unicameral legislature.)*

### 2010 cycle — 42 states (7 block-data states excluded)

| | | | | | | | |
|--|--|--|--|--|--|--|--|
| AK | AR | AZ | CA | CO | CT | DE | FL |
| GA | HI | IA | ID | IL | IN | KS | KY |
| LA | MA | MD | MI | MN | MO | MS | NC |
| NJ | NM | NV | NY | OH | OK | OR | PA |
| RI | SC | SD | TN | TX | UT | VA | WA |
| WI | WV | | | | | | |

**Excluded from 2010:** AL, ME, MT, ND, NH, VT, WY

### 2020 cycle — 40 states (5 block-data states excluded)

| | | | | | | | |
|--|--|--|--|--|--|--|--|
| AK | AL | AR | AZ | CO | CT | DE | FL |
| GA | IA | ID | IL | IN | KS | KY | LA |
| MA | MD | MI | MN | MO | MS | NC | NJ |
| NM | NV | NY | OH | OK | PA | RI | SC |
| SD | TN | TX | UT | VA | WA | WI | WV |

**Excluded from 2020:** MT, ND, NH, VT, WY

*(CA, HI, ME, OR also excluded from 2020 in the original pipeline — they lack VTD data for that cycle.)*

---

## Excluded States Summary

| State | 2010 excluded | 2020 excluded | Reason |
|-------|:---:|:---:|--------|
| AL | ✓ | — | VTDs too coarse for district population target |
| ME | ✓ | — | VTDs too coarse for district population target |
| MT | ✓ | ✓ | VTDs too coarse for district population target |
| ND | ✓ | ✓ | VTDs too coarse for district population target |
| NH | ✓ | ✓ | VTDs too coarse for district population target |
| VT | ✓ | ✓ | VTDs too coarse for district population target |
| WY | ✓ | ✓ | VTDs too coarse for district population target |

These states will be added back once the block-data pipeline is confirmed stable.
In the meantime their 2000-cycle analyses run normally (the 2000 cycle has no block-data states).

---

## Step-by-Step Cluster Instructions

### Step 1 — Pull the latest code

```bash
cd /path/to/fifty-states-main
git pull origin main
```

### Step 2 — Verify SLDL shapefiles are present

The prep scripts read TIGER SLDL boundary shapefiles to assign the enacted plan.
These must already be downloaded and extracted. If any are missing, run the download
scripts before proceeding:

```bash
# 2020-cycle shapefiles (needed for 2020s analyses)
python3 Download_2020_script.py

# 2010-cycle shapefiles (needed for 2010s analyses)
python3 Download_2013_script.py

# 2000-cycle shapefiles (needed for 2000s analyses)
python3 Download_2010_script.py
```

### Step 3 — Generate analysis scripts

This creates (or overwrites) the `01_prep`, `02_setup`, and `03_sim` scripts for all
130 VTD-only state-decade combinations, and extracts the SLDL shapefiles into
`data-raw/{STATE}/sldl_{YEAR}/`.

```bash
Rscript -e "setwd('$(pwd)'); source('analyses/00_generate_shd_analyses_vtd_only.R')"
```

Existing cached output files (`shp_vtd.rds`, `_map.rds`, `_plans.rds`, `_stats.csv`)
are protected by file-existence guards — states that already finished will be skipped
automatically.

### Step 4 — Create the log directory

```bash
mkdir -p logs
```

### Step 5 — Submit the batch job

```bash
sbatch analyses/run_shd_vtd_only.sh
```

This submits a SLURM array of 130 tasks. Each task runs one state-decade analysis
end-to-end (prep → setup → simulation → summary stats). Logs are written to
`logs/shd_vtd_{JOBID}_{TASKID}.out` and `.err`.

#### Memory and time guidance

| State size | Memory | Time |
|------------|--------|------|
| Small chambers (DE, RI, SD) | 8–16 GB | 2–4 h |
| Medium chambers (CO, GA, NC) | 32 GB | 6–8 h |
| Large chambers (CA, NY, TX) | 64 GB | 12–24 h |

The default job requests 32 GB and 12 hours, which covers most states. Resubmit
CA, NY, and TX individually with `--mem=64G` if they time out.

#### Resubmitting individual states

To rerun specific tasks (e.g., if a few states fail), find the 1-based position of the
state in the `ANALYSES` array in `run_shd_vtd_only.sh` and submit with `--array`:

```bash
# Example: resubmit tasks 12 and 47
sbatch --array=12,47 analyses/run_shd_vtd_only.sh
```

### Step 6 — Monitor progress

```bash
# Check job status
squeue -u $USER

# Tail a specific log
tail -f logs/shd_vtd_JOBID_TASKID.out

# Count completed _stats.csv files
find data-out -name "*_stats.csv" | wc -l
# Expected: up to 130 when all jobs complete
```

### Step 7 — Diagnose any failures

```bash
Rscript -e "setwd('$(pwd)'); source('analyses/diagnose_shd_failures.R')"
```

This scans all output directories, classifies failure stages (prep / setup / sim / stats),
and writes a diagnosis table to `data-out/combined/shd_diagnosis.csv`. Check the
console output for suspected causes and SLURM log error excerpts.

---

## Creating the Combined Summary CSV

Each completed analysis writes its own summary statistics to:

```
data-out/{STATE}_{YEAR}/{STATE}_shd_{YEAR}_stats.csv
```

To combine all completed runs into a single flat file, run the following from R in the
project root:

```r
library(dplyr)
library(readr)
library(here)

stats_files <- Sys.glob(here("data-out/*/*_shd_*_stats.csv"))

combined <- lapply(stats_files, function(f) {
    tryCatch(read_csv(f, show_col_types = FALSE), error = function(e) {
        warning("Could not read: ", f, " — ", conditionMessage(e))
        NULL
    })
}) |>
    Filter(Negate(is.null), x = _) |>
    bind_rows()

write_csv(combined, here("data-out/combined/shd_stats_all.csv"))
message("Combined ", length(stats_files), " files → ",
        nrow(combined), " rows written to data-out/combined/shd_stats_all.csv")
```

Or run it directly from the shell:

```bash
Rscript -e "
library(dplyr); library(readr); library(here)
f <- Sys.glob(here('data-out/*/*_shd_*_stats.csv'))
lapply(f, \(x) tryCatch(read_csv(x, show_col_types=FALSE), error=\(e) NULL)) |>
    Filter(Negate(is.null), x=_) |>
    bind_rows() |>
    write_csv(here('data-out/combined/shd_stats_all.csv'))
message('Done: ', length(f), ' files combined')
"
```

The output file `data-out/combined/shd_stats_all.csv` contains one row per simulated
plan per district, with columns for all compactness, partisan, and demographic metrics
computed by `add_summary_stats()`.

---

## Output Files (per state-decade)

| File | Description |
|------|-------------|
| `data-out/{ST}_{YR}/shp_vtd.rds` | `sf` data frame: VTD geometries + demographics + enacted plan |
| `data-out/{ST}_{YR}/{slug}_map.rds` | `redist_map` object used as SMC input |
| `data-out/{ST}_{YR}/{slug}_plans.rds` | `redist_plans` object: 10,000 sampled assignments |
| `data-out/{ST}_{YR}/{slug}_stats.csv` | Per-plan summary statistics (compactness, partisanship, demographics) |

---

## Simulation Parameters

| Parameter | Value |
|-----------|-------|
| Method | Sequential Monte Carlo (`redist_smc`) |
| Plans per run | 2,000 |
| Independent runs | 5 |
| Total plans | 10,000 |
| Population tolerance | 5% |
| County constraint | `pick_county_muni()` pseudo-county weighting |
| Random seed | Set to the redistricting year (2000, 2010, or 2020) |
