# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the **50-State Legislature Simulation Project** (ALARM Project + Jack Holland). It samples alternative redistricting plans for U.S. states using Sequential Monte Carlo (SMC) simulation via the `redist` R package, then compares enacted plans against sampled alternatives on metrics like compactness, partisan fairness, and demographic representation. Results are published to [Harvard Dataverse](https://doi.org/10.7910/DVN/SLCD3E).

## Loading the Package

The R utility functions are structured as an R package (`fifty.states`). Load all shared code with:

```r
devtools::load_all(".")
```

In RStudio: `Ctrl+Shift+L`

## Running an Analysis

Each state analysis lives in `analyses/{decade}/{STATE}_{type}_{year}/` and follows a strict 3-step pipeline. Run scripts in numbered order:

```r
# From an analysis directory:
source("01_prep_XX_cd_YYYY.R")   # Step 1: Download & prep Census/election data
source("02_setup_XX_cd_YYYY.R")  # Step 2: Build redist_map with constraints
source("03_sim_XX_cd_YYYY.R")    # Step 3: Run SMC simulation & compute stats
```

Or programmatically: `lapply(sort(Sys.glob("*.R")), source)`

## Creating a New Analysis

```r
devtools::load_all(".")
init_analysis(state = "GA", type = "cd", year = 2020)
```

This populates a new analysis folder from `R/template/` with placeholder substitution (`{STATE}`, `{SLUG}`, `{YEAR}`, etc.).

## Finalizing & Publishing

```r
finalize_analysis(state = "GA", type = "cd", year = 2020)  # Validate + publish to Dataverse
quality_control(state = "GA", type = "cd", year = 2020)     # Opens QC resources
```

## Architecture

- **`R/`** — Shared utility functions loaded as a package:
  - `management.R` — `init_analysis()`, `enforce_style()`, analysis scaffolding
  - `utils.R` — Census data download, VTD shapefile joining, VEST crosswalks
  - `summary_stats.R` — Computes all plan metrics (compactness, partisanship, demographics, splits)
  - `finalize.R` — Validation, Dataverse upload (`pub_dataverse()`)
  - `baf.R` — Block Assignment File operations
  - `fix_adj.R` — Adjacency graph repairs
  - `validate.R` — Validation plots (density, histograms, example districts)
  - `template/` — Parameterized templates for `01_prep`, `02_setup`, `03_sim`, and documentation

- **`analyses/`** — Self-contained per-state analysis folders organized by decade (`1990s/`, `2000s/`, `2010s/`, `2020s/`). Each produces:
  - `{SLUG}_map.rds` — `redist_map` object with demographics and geometry
  - `{SLUG}_plans.rds` — Matrix of 5000+ sampled district assignments
  - `{SLUG}_stats.csv` — Summary statistics per plan

- **`data-raw/`** — Unprocessed input data (not tracked in git)
- **`data-out/`** — Draft/unvalidated output (not tracked in git)

- **Python scripts** (`Download_2010_script.py`, `Download_2020_script.py`) — Download Census TIGER shapefiles for state legislative districts (SLDL/SLDU) by FIPS code. Require `requests`.

## Key Simulation Parameters

- Population tolerance: typically 0.005 (0.5%)
- Plans per simulation: 2000 plans × 5 independent runs
- Sampler: `redist_smc()` from the `redist` package
- Constraints: county splits, municipality preservation, adjacency

## Naming Conventions

Analysis slugs follow the pattern: `{STATE}_{type}_{year}` (e.g., `GA_cd_2010`)
- `type`: `cd` (congressional), `ssd` (state senate), `shd` (state house)
- `year`: redistricting cycle (2000, 2010, 2020)

## R Dependencies

Core packages: `redist` (>= 4.2.0), `redistmetrics`, `geomander`, `PL94171`, `sf`, `censable`, `cvap`, `tigris`, `dataverse`. Full list in `DESCRIPTION`.
