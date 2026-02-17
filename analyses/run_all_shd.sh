#!/bin/bash
#SBATCH --job-name=shd_sim
#SBATCH --output=logs/shd_%A_%a.out
#SBATCH --error=logs/shd_%A_%a.err
#SBATCH --time=12:00:00
#SBATCH --mem=32G
#SBATCH --cpus-per-task=4
#SBATCH --array=1-142

###############################################################################
# Slurm array job to run all state house redistricting simulations
#
# Usage:
#   mkdir -p logs
#   sbatch analyses/run_all_shd.sh
#
# Each array task runs one state-decade analysis end-to-end (prep, setup, sim).
# Adjust --mem and --time based on state size:
#   Small states (DE, RI, WY): ~8G, 2h
#   Medium states (GA, NC, VA): ~32G, 8h
#   Large states (CA, TX, NY): ~64G, 12-24h
###############################################################################

# List of all state-decade analysis directories
# This is populated by 00_generate_shd_analyses.R
ANALYSES=(
    # 2000s (48 states — AK lacks VTD data, NE unicameral)
    "2000s/AL_shd_2000" "2000s/AR_shd_2000" "2000s/AZ_shd_2000" "2000s/CA_shd_2000"
    "2000s/CO_shd_2000" "2000s/CT_shd_2000" "2000s/DE_shd_2000" "2000s/FL_shd_2000"
    "2000s/GA_shd_2000" "2000s/HI_shd_2000" "2000s/IA_shd_2000" "2000s/ID_shd_2000"
    "2000s/IL_shd_2000" "2000s/IN_shd_2000" "2000s/KS_shd_2000" "2000s/KY_shd_2000"
    "2000s/LA_shd_2000" "2000s/MA_shd_2000" "2000s/MD_shd_2000" "2000s/ME_shd_2000"
    "2000s/MI_shd_2000" "2000s/MN_shd_2000" "2000s/MO_shd_2000" "2000s/MS_shd_2000"
    "2000s/MT_shd_2000" "2000s/NC_shd_2000" "2000s/ND_shd_2000" "2000s/NH_shd_2000"
    "2000s/NJ_shd_2000" "2000s/NM_shd_2000" "2000s/NV_shd_2000" "2000s/NY_shd_2000"
    "2000s/OH_shd_2000" "2000s/OK_shd_2000" "2000s/OR_shd_2000" "2000s/PA_shd_2000"
    "2000s/RI_shd_2000" "2000s/SC_shd_2000" "2000s/SD_shd_2000" "2000s/TN_shd_2000"
    "2000s/TX_shd_2000" "2000s/UT_shd_2000" "2000s/VA_shd_2000" "2000s/VT_shd_2000"
    "2000s/WA_shd_2000" "2000s/WI_shd_2000" "2000s/WV_shd_2000" "2000s/WY_shd_2000"
    # 2010s (49 states — NE unicameral)
    "2010s/AK_shd_2010" "2010s/AL_shd_2010" "2010s/AR_shd_2010" "2010s/AZ_shd_2010"
    "2010s/CA_shd_2010" "2010s/CO_shd_2010" "2010s/CT_shd_2010" "2010s/DE_shd_2010"
    "2010s/FL_shd_2010" "2010s/GA_shd_2010" "2010s/HI_shd_2010" "2010s/IA_shd_2010"
    "2010s/ID_shd_2010" "2010s/IL_shd_2010" "2010s/IN_shd_2010" "2010s/KS_shd_2010"
    "2010s/KY_shd_2010" "2010s/LA_shd_2010" "2010s/MA_shd_2010" "2010s/MD_shd_2010"
    "2010s/ME_shd_2010" "2010s/MI_shd_2010" "2010s/MN_shd_2010" "2010s/MO_shd_2010"
    "2010s/MS_shd_2010" "2010s/MT_shd_2010" "2010s/NC_shd_2010" "2010s/ND_shd_2010"
    "2010s/NH_shd_2010" "2010s/NJ_shd_2010" "2010s/NM_shd_2010" "2010s/NV_shd_2010"
    "2010s/NY_shd_2010" "2010s/OH_shd_2010" "2010s/OK_shd_2010" "2010s/OR_shd_2010"
    "2010s/PA_shd_2010" "2010s/RI_shd_2010" "2010s/SC_shd_2010" "2010s/SD_shd_2010"
    "2010s/TN_shd_2010" "2010s/TX_shd_2010" "2010s/UT_shd_2010" "2010s/VA_shd_2010"
    "2010s/VT_shd_2010" "2010s/WA_shd_2010" "2010s/WI_shd_2010" "2010s/WV_shd_2010"
    "2010s/WY_shd_2010"
    # 2020s (45 states — CA, HI, ME, OR lack VTD data)
    "2020s/AK_shd_2020" "2020s/AL_shd_2020" "2020s/AR_shd_2020" "2020s/AZ_shd_2020"
    "2020s/CO_shd_2020" "2020s/CT_shd_2020" "2020s/DE_shd_2020" "2020s/FL_shd_2020"
    "2020s/GA_shd_2020" "2020s/IA_shd_2020" "2020s/ID_shd_2020" "2020s/IL_shd_2020"
    "2020s/IN_shd_2020" "2020s/KS_shd_2020" "2020s/KY_shd_2020" "2020s/LA_shd_2020"
    "2020s/MA_shd_2020" "2020s/MD_shd_2020" "2020s/MI_shd_2020" "2020s/MN_shd_2020"
    "2020s/MO_shd_2020" "2020s/MS_shd_2020" "2020s/MT_shd_2020" "2020s/NC_shd_2020"
    "2020s/ND_shd_2020" "2020s/NH_shd_2020" "2020s/NJ_shd_2020" "2020s/NM_shd_2020"
    "2020s/NV_shd_2020" "2020s/NY_shd_2020" "2020s/OH_shd_2020" "2020s/OK_shd_2020"
    "2020s/PA_shd_2020" "2020s/RI_shd_2020" "2020s/SC_shd_2020" "2020s/SD_shd_2020"
    "2020s/TN_shd_2020" "2020s/TX_shd_2020" "2020s/UT_shd_2020" "2020s/VA_shd_2020"
    "2020s/VT_shd_2020" "2020s/WA_shd_2020" "2020s/WI_shd_2020" "2020s/WV_shd_2020"
    "2020s/WY_shd_2020"
)

# Get this task's analysis
IDX=$((SLURM_ARRAY_TASK_ID - 1))
ANALYSIS=${ANALYSES[$IDX]}

echo "=== Running analysis: $ANALYSIS ==="
echo "Start time: $(date)"

cd "$SLURM_SUBMIT_DIR"

# Run the three-step pipeline
Rscript -e "
setwd('$(pwd)')
source('analyses/${ANALYSIS}/01_prep_$(basename $ANALYSIS).R')
source('analyses/${ANALYSIS}/02_setup_$(basename $ANALYSIS).R')
source('analyses/${ANALYSIS}/03_sim_$(basename $ANALYSIS).R')
"

echo "=== Finished: $ANALYSIS ==="
echo "End time: $(date)"
