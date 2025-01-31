#!/bin/bash

#SBATCH --job-name="parabricks_deepvariant_germline"
#SBATCH --output="%x_%j.out"
#SBATCH --error="%x_%j.err"
#SBATCH --nodes=1
#SBATCH --ntasks=16
#SBATCH --cpus-per-task=4
#SBATCH --time=0-02:00:00
#SBATCH --mem=256G
#SBATCH --account=s04
#SBATCH --gres=gpu:4
#SBATCH --partition=gpu_h100_64C_128T_2TB_co_pi

# gpu_l40s_64C_128T_1TB
# gpu_h100_64C_128T_2TB

# Aim: run the NVidia clara parabricks deepvariant_germline (v4.4.0) on 1 sample read pair
# script: slurm_deepvariant_germline.sh
#   run with 'sbatch scripts/slurm_deepvariant_germline.sh reads/SRR29676022_1.fq.gz 4'
# author: SP@NC; 2025-01-21 v1.1

# Check if an argument is provided
if [ $# -eq 0 ]; then
    echo "Error: Please provide the path to the reads_1.fq.gz file. \
          Usage: sbatch scripts/slurm_deepvariant_germline.sh reads/<read1.fq.gz>"
    exit 1
fi

# set the $1 argument to the path to read_1.fq.gz provided by the user
fq=${1}

# use 4 GPU by default unless stated with $2
numgpu=${2:-4}

# set WORKDIR
WORKDIR="/data/projects/s04/wgs_variant_analysis"

# set pfx
pfx=$(basename "${fq%_1.fq.gz}")_${numgpu}

# output folder for mappings
outbam="mappings_h100_${numgpu}gpu"
mkdir -p "${outbam}"

# output folder for variants
outvcf="variants_XYhap_h100_${numgpu}gpu"
mkdir -p "${outvcf}"

# output folder for logs
outlogs="logs_XYhap_h100_${numgpu}gpu"
mkdir -p "${outlogs}"

#######################
# additional arguments
#######################

# locate the singularity SIF file for the latest "NVidia clara parabricks" workflow
singimg="${WORKDIR}/bin/clara-parabricks_4.4.0-1.sif"

# run settings (platform-dependent, this should migrate into a config file)
refidx="mRatBN7.2.fa"
knownsites="rattus_norvegicus.vcf.gz"
optdist=2500
platform="Illumina"

# optional parameter for male rat genomes
# list of known haploid chromosomes in this assembly (X, Y, Y_unloc4)
hapchr="X,Y,MU150192.1"

# deduce fq1
fq1=$(basename "${fq}")

# deduce fq2
fq2=${fq1/_1.fq.gz/_2.fq.gz}

# build and run singularity command
echo "Starting slurm_deepvariant_germline.sh job execution..." > ${WORKDIR}/${outlogs}/${pfx}_slurm_resources.txt
echo $(date) >> ${WORKDIR}/${outlogs}/${pfx}_slurm_resources.txt

singularity run --nv \
    --bind "${WORKDIR}:/workdir" \
    --bind "${TMPDIR}:/tmp" \
    --pwd "/workdir" \
    ${singimg} \
    pbrun deepvariant_germline \
    --gpusort \
    --gpuwrite \
    --num-gpus ${numgpu} \
    --bwa-options '-M -K 10000000' \
    --optical-duplicate-pixel-distance "${optdist}" \
    --read-group-sm "${pfx}" \
    --read-group-lb "lib_${pfx}" \
    --read-group-pl "${platform}" \
    --read-group-id-prefix "${pfx}" \
    --ref "/workdir/bwaidx/${refidx}" \
    --in-fq "/workdir/reads/${fq1}" "/workdir/reads/${fq2}" \
    --knownSites "/workdir/reference/${knownsites}" \
    --haploid-contigs "${hapchr}" \
    --out-bam "/workdir/${outbam}/${pfx}_mrkdup.bam" \
    --out-recal-file "/workdir/${outbam}/${pfx}_recal.txt" \
    --out-duplicate-metrics "/workdir/${outbam}/${pfx}_duplicate_metrics" \
    --out-variants "/workdir/${outvcf}/${pfx}_XYhap.g.vcf.gz" \
    --gvcf \
    --tmp-dir "/tmp"

# cleanup

# rename output and error files to include ${pfx} and move them
mv ${outlogs}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}.out ${outlogs}/${pfx}_${SLURM_JOB_NAME}_${SLURM_JOB_ID}.out
mv ${outlogs}/${SLURM_JOB_NAME}_${SLURM_JOB_ID}.err ${outlogs}/${pfx}_${SLURM_JOB_NAME}_${SLURM_JOB_ID}.err

# save resource usage for logging purposes
$(date) >> ${WORKDIR}/${outlogs}/${pfx}_slurm_resources.txt
sacct -j $SLURM_JOB_ID --format=JobID,JobName,State,ExitCode,Elapsed,CPUTime,TotalCPU,ReqCPUS,AllocCPUS,AveRSS,MaxRSS,ReqMem,AveVMSize,MaxVMSize \
      >> ${WORKDIR}/${outlogs}/${pfx}_slurm_resources.txt
echo "Cleanup complete. Exiting."

# terminate slurm queued session now to run next in queue
exit 0
