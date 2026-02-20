#!/bin/bash
#SBATCH --job-name=shd_2000s
#SBATCH --output=logs/shd_2000s_%A_%a.out
#SBATCH --error=logs/shd_2000s_%A_%a.err
#SBATCH --time=12:00:00
#SBATCH --mem=32G
#SBATCH --cpus-per-task=4
#SBATCH --array=1-48

###############################################################################
# Slurm array job — 2000s SHD analyses (48 states; AK lacks VTD data, NE unicameral)
#
# Workflow (run one batch at a time to manage storage):
#   mkdir -p logs
#   sbatch analyses/run_shd_2000s.sh   # Step 1 of 3
#   # After jobs finish: transfer outputs, then clear data-out/ before next batch
#   sbatch analyses/run_shd_2010s.sh   # Step 2 of 3
#   sbatch analyses/run_shd_2020s.sh   # Step 3 of 3
###############################################################################

ANALYSES=(
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
