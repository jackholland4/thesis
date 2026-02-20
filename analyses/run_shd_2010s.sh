#!/bin/bash
#SBATCH --job-name=shd_2010s
#SBATCH --output=logs/shd_2010s_%A_%a.out
#SBATCH --error=logs/shd_2010s_%A_%a.err
#SBATCH --time=12:00:00
#SBATCH --mem=32G
#SBATCH --cpus-per-task=4
#SBATCH --array=1-49

###############################################################################
# Slurm array job — 2010s SHD analyses (49 states; NE unicameral)
#
# Run after 2000s jobs finish and outputs have been transferred/cleared.
###############################################################################

ANALYSES=(
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
