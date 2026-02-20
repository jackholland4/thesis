#!/bin/bash
#SBATCH --job-name=shd_2020s
#SBATCH --output=logs/shd_2020s_%A_%a.out
#SBATCH --error=logs/shd_2020s_%A_%a.err
#SBATCH --time=12:00:00
#SBATCH --mem=32G
#SBATCH --cpus-per-task=4
#SBATCH --array=1-45

###############################################################################
# Slurm array job — 2020s SHD analyses (45 states; CA, HI, ME, OR lack VTD data, NE unicameral)
#
# Run after 2010s jobs finish and outputs have been transferred/cleared.
###############################################################################

ANALYSES=(
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

IDX=$((SLURM_ARRAY_TASK_ID - 1))
ANALYSIS=${ANALYSES[$IDX]}

echo "=== Running analysis: $ANALYSIS ==="
echo "Start time: $(date)"

cd "$SLURM_SUBMIT_DIR"

Rscript -e "
setwd('$(pwd)')
source('analyses/${ANALYSIS}/01_prep_$(basename $ANALYSIS).R')
source('analyses/${ANALYSIS}/02_setup_$(basename $ANALYSIS).R')
source('analyses/${ANALYSIS}/03_sim_$(basename $ANALYSIS).R')
"

echo "=== Finished: $ANALYSIS ==="
echo "End time: $(date)"
