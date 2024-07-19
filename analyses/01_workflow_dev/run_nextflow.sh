#! /usr/bin/env bash

# Exit on unset variables, errors, or pipe failures
# Prevent clean up of working dirs when prototyping
set -euo pipefail

function get_cluster_name {
    if command -v sacctmgr >/dev/null 2>&1; then
        # Only return cluster names we're catering for
        sacctmgr show cluster -P -n \
        | cut -f1 -d'|' \
        | grep "rackham\|dardel"
    fi
}

function run_nextflow {
    PROFILE="${PROFILE:-$1}"                    # Profile to use (values: uppmax, pdc_kth)
    STORAGEALLOC="$2"                           # NAISS storage allocation (path)
    WORKDIR="${PWD/analyses/nobackup}/nxf-work" # Nextflow work directory
    RESULTS="${PWD/analyses/data/outputs}"      # Path to store results from Nextflow

    # Path to Nextflow script
    SCRIPT="${SCRIPT:-$STORAGEALLOC/workflow/main.nf}"

    # Set common path to store all Singularity containers
    export NXF_SINGULARITY_CACHEDIR="${PWD/analyses*/nobackup}/singularity-cache"

    # Activate shared Nextflow environment
    eval "$(conda shell.bash hook)"
    conda activate "${STORAGEALLOC}/conda/nextflow-env"

    # Clean results folder if last run resulted in error
    if [ "$( nextflow log | awk -F $'\t' '{ last=$4 } END { print last }' )" == "ERR" ]; then
        echo "WARN: Cleaning results folder due to previous error" >&2
        rm -rf "$RESULTS"
    fi

    # Run Nextflow
    nextflow run "$SCRIPT" \
        -profile "$PROFILE" \
        -work-dir "$WORKDIR" \
        -resume \
        -ansi-log false \
        -params-file params.yml \
        --outdir "$RESULTS"

    # Clean up Nextflow cache to remove unused files
    nextflow clean -f -before "$( nextflow log -q | tail -n 1 )"
    # Clean up empty work directories
    find "$WORKDIR" -type d -empty -delete
    # Use `nextflow log` to see the time and state of the last nextflow executions.

}

# Detect cluster name ( rackham, dardel )
cluster=$( get_cluster_name )
echo "Running on HPC=$cluster."
# Set project dir
project_dir=$( basename $( basename "$PWD" ) )

# Run Nextflow with appropriate settings
if [ "$cluster" == "rackham" ]; then
    run_nextflow uppmax "$project_dir"
elif [ "$cluster" == "dardel" ]; then
    module load PDC apptainer
    run_nextflow pdc_kth "$project_dir"
else 
    echo "Error: unrecognised cluster '$cluster'." >&2
    exit 1
fi
