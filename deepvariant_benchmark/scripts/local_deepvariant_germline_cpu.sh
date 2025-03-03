#!/bin/bash

# Aim: run the Google deepvariant_germline (v1.8.0) on 1 sample read pair using CPU
# script: local_deepvariant_germline_CPU.sh
# author: SP@NC; 2025-01-28 v1.2
# Usage: scripts/local_deepvariant_germline_CPU.sh reads/SRR29676022_1.fq.gz
# Requirements:
# * existing conda env 'bwa_0.7.18' with bwa, samtools, gatk4
# * deepvariant sif file created with
#   BIN_VERSION="1.8.0"
#   # BIN_VERSION="1.8.0-gpu"
#   mkdir -p $PWD/bin
#   singularity pull $PWD/bin/deepvariant_${BIN_VERSION}.sif \
#     docker://google/deepvariant:"${BIN_VERSION}"

# exit on any error
set -e

# Check if an argument is provided
if [ $# -eq 0 ]; then
    echo "Error: Please provide the path to the reads_1.fq.gz file. \
          Usage: scripts/local_deepvariant_germline_CPU.shh reads/<read1.fq.gz>"
    exit 1
fi

# set the $1 argument to the path to read_1.fq.gz provided by the user
fq=${1}

# NOTE: the conda env defined below contains bwa, samtools, and gatk4
myenv=bwa_0.7.18
source /etc/profile.d/conda.sh
conda activate ${myenv} || \
  ( echo "# the conda environment ${myenv} was not found on this machine" ;
    echo "# please read the top part of the script!" \
    && exit 1 )

# Check if DeepVariant SIF file exists
BIN_VERSION="1.8.0"
export simimg="$PWD/bin/deepvariant_${BIN_VERSION}.sif"
if [ ! -f "${simimg}" ]; then
    echo "Error: DeepVariant SIF file not found at $PWD/bin/deepvariant_${BIN_VERSION}.sif"
    echo "Please ensure the file is present before running this script."
    exit 1
fi

###################
# custom functions
###################

# Function to run a command and log its output
run_and_log() {
    local cmd="$1"
    local log_file="$2"
    local description="$3"

    echo "# ${description}" | tee -a "${log_file}"
    echo "# ${cmd}" | tee -a "${log_file}"
    { time eval ${cmd}; } 2>&1 | tee -a "${log_file}"
}

# Function for BWA mem mapping and sorting by queryname
bwa_mem_and_sort() {
    local cmd="bwa mem \
        -t ${nthr} \
        -K 10000000 \
        -R \"${RGTAG}\" \
        ${WORKDIR}/${bwadir}/${refidx} \
        ${WORKDIR}/reads/${fq1} ${WORKDIR}/reads/${fq2} | \
          gatk SortSam \
          --java-options -Xmx${jram} \
          --MAX_RECORDS_IN_RAM 5000000 \
          --TMP_DIR ${WORKDIR}/tmpfiles \
          -I /dev/stdin \
          -O ${WORKDIR}/${outbam}/${pfx}_cpu_qn.bam \
          --SORT_ORDER queryname"
    
    run_and_log "${cmd}" "${WORKDIR}/${outlogs}/${pfx}_bwa_mapping_sort.out" "BWA mem mapping and sorting by queryname"
}

# Function for marking duplicates
mark_duplicates() {
    local cmd="java -Xmx${jram} \
        -jar ${GATK_PATH}/gatk.jar MarkDuplicates \
        --TMP_DIR ${WORKDIR}/tmpfiles \
        --OPTICAL_DUPLICATE_PIXEL_DISTANCE ${optdist} \
        --ASSUME_SORT_ORDER queryname \
        -I ${WORKDIR}/${outbam}/${pfx}_cpu_qn.bam \
        -O ${WORKDIR}/${outbam}/${pfx}_mrkdup_cpu_qn.bam \
        -M ${WORKDIR}/${outbam}/${pfx}_cpu_duplicate_metrics_co"
    
    run_and_log "${cmd}" "${WORKDIR}/${outlogs}/${pfx}_bwa_mapping.out" "Marking duplicates"
}

# Function for sorting reads by coordinate
sort_by_coordinate() {
    local cmd="java -Xmx${jram} \
        -jar ${GATK_PATH}/gatk.jar SortSam \
        --java-options -Xmx${jram} \
        --MAX_RECORDS_IN_RAM 5000000 \
        --TMP_DIR ${WORKDIR}/tmpfiles \
        -I ${WORKDIR}/${outbam}/${pfx}_mrkdup_cpu_qn.bam \
        -O ${WORKDIR}/${outbam}/${pfx}_mrkdup_cpu_co.bam \
        --SORT_ORDER queryname"
    
    run_and_log "${cmd}" "${WORKDIR}/${outlogs}/${pfx}_bwa_mapping.out" "Sorting by coordinate"
}

# Function for GATK4 BaseRecalibrator
base_recalibrator() {
    local cmd="java -Xmx${jram} \
        -jar ${GATK_PATH}/gatk.jar BaseRecalibrator \
        --tmp-dir ${WORKDIR}/tmpfiles \
        --input ${WORKDIR}/${outbam}/${pfx}_mrkdup_cpu_co.bam \
        --output ${WORKDIR}/${outbam}/${pfx}_recal_cpu.table \
        --known-sites ${WORKDIR}/${refdir}/${knownsites} \
        --reference ${WORKDIR}/${refdir}/${refidx}"
    
    run_and_log "${cmd}" "${WORKDIR}/${outlogs}/${pfx}_bwa_mapping.out" "BaseRecalibrator"
}

# Function for GATK4 ApplyBQSR
apply_bqsr() {
    local cmd="java -Xmx${jram} \
        -jar ${GATK_PATH}/gatk.jar ApplyBQSR \
        --tmp-dir  ${WORKDIR}/tmpfiles \
        -R ${WORKDIR}/${refdir}/${refidx} \
        -I ${WORKDIR}/${outbam}/${pfx}_mrkdup_cpu_co.bam \
        --bqsr-recal-file ${WORKDIR}/${outbam}/${pfx}_recal_cpu.table \
        -O ${WORKDIR}/${outbam}/${pfx}_recal_cpu.bam"
    
    run_and_log "${cmd}" "${WORKDIR}/${outlogs}/${pfx}_bwa_mapping.out" "ApplyBQSR"
}

# Function to run DeepVariant
run_deepvariant() {
    local hapchr="X,Y,MU150192.1"
    local model="WGS"

    local cmd="singularity run \
      --cleanenv \
      --bind \"${WORKDIR}\":\"/workdir\" \
      --pwd \"/workdir\" \
      \"${simimg}\" \
      /opt/deepvariant/bin/run_deepvariant \
      --model_type \"${model}\" \
      --ref \"/workdir/${refdir}/${refidx}\" \
      --haploid_contigs \"${hapchr}\" \
      --reads \"/workdir/${outbam}/${pfx}_recal_cpu.bam\" \
      --output_vcf \"/workdir/${outvcf}/${pfx}_XYhap.vcf.gz\" \
      --output_gvcf \"/workdir/${outvcf}/${pfx}_XYhap.g.vcf.gz\" \
      --num_shards \"${nthr}\" \
      --vcf_stats_report=true \
      --logging_dir \"/workdir/${outlogs}\" \
      --intermediate_results_dir \"/workdir/tmpfiles\" \
      --runtime_report"
    
    run_and_log "${cmd}" "${WORKDIR}/${outlogs}/${pfx}_deepvariant.out" "Running DeepVariant"
}

#########################################
# Export variables used across functions
#########################################

##############################
# resources-related arguments
##############################

# num threads
export nthr=40

# speedup GATK with more RAM
export jram="64G"

# define path to jar file
# NOTE: aliases have been added there to simplify the path and jar name
# default install to $CONDA_PREFIX/share/gatk4-4.6.1.0-0/gatk-package-4.6.1.0-local.jar
export GATK_PATH="$CONDA_PREFIX/share/gatk4"

###############
# IO variables
###############

# set WORKDIR and go
export WORKDIR=$PWD

# set pfx
export pfx=$(basename "${fq%_1.fq.gz}")

# output folder for mappings
export outbam="mappings_${nthr}cpu"
mkdir -p "${outbam}"

# output folder for variants
export outvcf="variants_XYhap_${nthr}cpu"
mkdir -p "${outvcf}"

# output folder for logs
export outlogs="logs_XYhap_${nthr}cpu"
mkdir -p "${outlogs}"

# folder for intermediate files to save /tmp
mkdir -p ${WORKDIR}/tmpfiles

###########################
# genome-related arguments
###########################

export bwadir="bwaidx"
export refidx="mRatBN7.2.fa"
export refdir="reference"
export knownsites="rattus_norvegicus.vcf.gz"
export optdist=2500
export platform="Illumina"

###########################
# sample-related arguments
###########################

# deduce fq1
export fq1=$(basename "${fq}")

# deduce fq2
export fq2=${fq1/_1.fq.gz/_2.fq.gz}

# define read-group tag
export RGTAG="@RG\\tID:${pfx}\\tLB:lib_${pfx}\\tPL:${platform}\\tSM:${pfx}\\tPU:${pfx}"

##################
# Main execution #
##################

# NOTE: when resuming after failure, comment all step already performed

bwa_mem_and_sort
mark_duplicates
sort_by_coordinate
base_recalibrator
apply_bqsr
conda deactivate
run_deepvariant

exit 0
