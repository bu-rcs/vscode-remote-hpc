#!/bin/bash

# The time you expect a job to start in (seconds)
# If a job doesn't start within this time, the script will exit and cancel the pending job
TIMEOUT=1800


####################
# don't edit below this line
####################

function usage ()
{
    echo "Usage :  $0 [command | sbatch-options]

    General commands:
    list      List running vscode-remote jobs
    cancel    Cancels all running vscode-remote jobs
    ssh       SSH into the node of a running job
    help      Display this message

    Job options:
    Pass sbatch options directly. A unique job name is derived from the options
    using an md5 hash, so reconnections work automatically.

    Use -J <label> (or --job-name <label>) to distinguish multiple jobs with
    identical resource flags. The label is prepended to the hash
    (e.g. jobA.HASH.username). This flag is consumed by this script and is not
    passed to sbatch.

    Use -z <modules> to load a comma-separated list of Lmod modules on the
    compute node (e.g. -z openmpi/4.1.5,quantumespresso/7.3).

    Examples:

        Host vscode-remote-cpu-4
            User USERNAME
            IdentityFile ~/.ssh/vscode-remote
            ProxyCommand ssh HPC-LOGIN \"~/bin/vscode-remote -c 4 -t 24:00:00 --mem=32G\"
            StrictHostKeyChecking no

        Host vscode-remote-cpu-1
            User USERNAME
            IdentityFile ~/.ssh/vscode-remote
            ProxyCommand ssh HPC-LOGIN \"~/bin/vscode-remote -c 1 --mem=8G\"
            StrictHostKeyChecking no

        Host vscode-remote-gpu
            User USERNAME
            IdentityFile ~/.ssh/vscode-remote
            ProxyCommand ssh HPC-LOGIN \"~/bin/vscode-remote -c 8 --gpus=1 -t 04:00:00\"
            StrictHostKeyChecking no

        # Two independent 1-core sessions:
        Host vscode-remote-cpu-1a
            User USERNAME
            IdentityFile ~/.ssh/vscode-remote
            ProxyCommand ssh HPC-LOGIN \"~/bin/vscode-remote -c 1 -J jobA\"
            StrictHostKeyChecking no

        Host vscode-remote-cpu-1b
            User USERNAME
            IdentityFile ~/.ssh/vscode-remote
            ProxyCommand ssh HPC-LOGIN \"~/bin/vscode-remote -c 1 -J jobB\"
            StrictHostKeyChecking no
    "
}

function parse_sbatch_args () {
    # Extract -J/--job-name <label> from args (sets SBATCH_JOB_LABEL).
    # Extract -z <modules> from args (sets SBATCH_MODULES) - a comma-separated
    # list of Lmod modules to load on the compute node.
    # All remaining args are stored in SBATCH_ARGS_ARRAY for passing to sbatch.
    SBATCH_JOB_LABEL=""
    SBATCH_MODULES=""
    SBATCH_ARGS_ARRAY=()

    while [ $# -gt 0 ]; do
        case "$1" in
            -J|--job-name)
                if [ $# -gt 1 ]; then SBATCH_JOB_LABEL="$2"; shift 2; else shift; fi
                ;;
            --job-name=*)
                SBATCH_JOB_LABEL="${1#*=}"; shift
                ;;
            -z)
                if [ $# -gt 1 ]; then SBATCH_MODULES="$2"; shift 2; else shift; fi
                ;;
            *)
                SBATCH_ARGS_ARRAY+=("$1"); shift
                ;;
        esac
    done
}

function compute_job_prefix () {
    # Build the stable job-name prefix used to find/submit jobs:
    #   vscode-remote-[LABEL.]HASH.USER
    # HASH is the md5 of the sbatch args (excluding the label) plus the module
    # list, so the same resource spec and modules always map to the same job,
    # enabling automatic reconnection (and distinct module sets get distinct
    # jobs).
    local hash
    hash=$(echo "${SBATCH_ARGS_ARRAY[*]} ${SBATCH_MODULES}" | md5sum | cut -d ' ' -f 1)

    local prefix="vscode-remote-"
    if [ -n "$SBATCH_JOB_LABEL" ]; then
        prefix="${prefix}${SBATCH_JOB_LABEL}."
    fi
    prefix="${prefix}${hash}.${USER}"
    echo "$prefix"
}

function query_slurm () {
    # Find the first job whose full name starts with $prefix. Sets JOB_ID,
    # JOB_FULLNAME, JOB_STATE, JOB_NODE, JOB_PORT (port is the trailing -PORT
    # field of the job name).
    local prefix="${1:-$JOB_NAME}"

    JOB_ID=""
    JOB_FULLNAME=""
    JOB_STATE=""
    JOB_NODE=""
    JOB_PORT=""

    while read -r jid full state node; do
        if [[ "$full" == "$prefix"* ]]; then
            JOB_ID="$jid"
            JOB_FULLNAME="$full"
            JOB_STATE="$state"
            JOB_NODE="$node"
            JOB_PORT="$(echo "$full" | rev | cut -d'-' -f1 | rev)"
            >&2 echo "Job is $JOB_STATE ( id: $JOB_ID, name: $JOB_FULLNAME${JOB_NODE:+, node: $JOB_NODE} )"
            break
        fi
    done < <(squeue --me --states=R,PD,S,CF,RF,RH,RQ -h -O JobID:" ",Name:" ",State:" ",NodeList:" " 2>/dev/null)
}

function collect_jobs () {
    # Collect (jid|full_name|state|node|port) for jobs with name starting with "$1"
    local prefix="$1"
    JOB_ROWS=()

    while read -r jid full state node; do
        if [[ "$full" == "$prefix"* ]]; then
            local port
            port="$(echo "$full" | rev | cut -d'-' -f1 | rev)"
            JOB_ROWS+=("$jid|$full|$state|$node|$port")
        fi
    done < <(squeue --me --states=R,PD,S,CF,RF,RH,RQ -h -O JobID:" ",Name:" ",State:" ",NodeList:" " 2>/dev/null)
}

function cleanup () {
    if [ ! -z "${JOB_SUBMIT_ID:-}" ]; then
        scancel "$JOB_SUBMIT_ID" 2>/dev/null
        >&2 echo "Cancelled pending job $JOB_SUBMIT_ID"
    fi
}

function timeout () {
    if (( $(date +%s)-START > TIMEOUT )); then
        >&2 echo "Timeout, exiting..."
        cleanup
        exit 1
    fi
}

function cancel () {
    # Cancel all running/pending vscode-remote jobs (any options)
    while true; do
        collect_jobs "${JOB_NAME}-"
        if [ ${#JOB_ROWS[@]} -eq 0 ]; then
            break
        fi
        for row in "${JOB_ROWS[@]}"; do
            jid="$(echo "$row" | cut -d'|' -f1)"
            full="$(echo "$row" | cut -d'|' -f2)"
            node="$(echo "$row" | cut -d'|' -f4)"
            echo "Cancelling job $jid (${full}${node:+ on $node})"
            scancel "$jid" 2>/dev/null
        done
        timeout
        sleep 2
    done
}

function list () {
    squeue --me -O JobID:12,Partition:14,Name:45,State:12,TimeUsed:12,TimeLimit:12,NodeList:20 2>/dev/null \
        | grep -E "JOBID|vscode-remote"
}

function ssh_connect () {
    # SSH into the node of a running vscode-remote job (any options)
    collect_jobs "${JOB_NAME}-"

    if [ ${#JOB_ROWS[@]} -eq 0 ]; then
        echo "No running job found"
        exit 1
    fi

    if [ ${#JOB_ROWS[@]} -gt 1 ]; then
        echo "Multiple jobs found, please choose:"
        i=1
        for row in "${JOB_ROWS[@]}"; do
            full="$(echo "$row" | cut -d'|' -f2)"
            state="$(echo "$row" | cut -d'|' -f3)"
            node="$(echo "$row" | cut -d'|' -f4)"
            port="$(echo "$row" | cut -d'|' -f5)"
            printf "%d) %s (state: %s%s%s)\n" "$i" "$full" "$state" "${node:+, node: }" "${node:-}"
            i=$((i+1))
        done
        read -p "Enter a number: " choice
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#JOB_ROWS[@]} ]; then
            echo "Invalid choice"
            exit 1
        fi
        row="${JOB_ROWS[$((choice-1))]}"
    else
        row="${JOB_ROWS[0]}"
    fi

    node="$(echo "$row" | cut -d'|' -f4)"
    port="$(echo "$row" | cut -d'|' -f5)"
    full="$(echo "$row" | cut -d'|' -f2)"

    if [ -z "$node" ] || [ -z "$port" ]; then
        echo "Selected job is not yet running on a node (name: $full)"
        exit 1
    fi

    echo "Connecting to $node:$port via SSH"
    ssh -p "$port" "$node"
}

function connect () {
    local job_prefix
    job_prefix=$(compute_job_prefix)

    query_slurm "$job_prefix"

    if [ -z "${JOB_STATE}" ]; then
        PORT=$(shuf -i 10000-65000 -n 1)
        # Submit job; -J sets the full job name (prefix + port for later discovery).
        # -o/-e default to /dev/null but may be overridden by the user's args,
        # which follow on the command line.
        submit_output=$(sbatch -o /dev/null -e /dev/null -J "$job_prefix-$PORT" "${SBATCH_ARGS_ARRAY[@]}" "$SCRIPT_DIR/vscode-remote-job.sh" "$PORT" "$SBATCH_MODULES" 2>&1)
        JOB_SUBMIT_ID=$(echo "$submit_output" | grep -oE '[0-9]+' | head -1)
        >&2 echo "Submitted new job (id: $JOB_SUBMIT_ID, name: $job_prefix-$PORT)"
        >&2 echo "  sbatch args: ${SBATCH_ARGS_ARRAY[*]}"
    fi

    while [ ! "$JOB_STATE" == "RUNNING" ]; do
        timeout
        sleep 5
        query_slurm "$job_prefix"
    done

    >&2 echo "Connecting to $JOB_NODE"

    while ! nc -z "$JOB_NODE" "$JOB_PORT"; do
        timeout
        sleep 1
    done

    nc "$JOB_NODE" "$JOB_PORT"
}

if [ ! -z "${1:-}" ]; then
    JOB_NAME=vscode-remote
    SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
    START=$(date +%s)
    trap "cleanup && exit 1" INT TERM
    case $1 in
        list)   list ;;
        cancel) cancel ;;
        ssh)    ssh_connect ;;
        help)   usage ;;
        -*)     parse_sbatch_args "$@"; connect ;;
        *)
            >&2 echo "Unknown command: $1"
            usage
            exit 1
            ;;
    esac
    exit 0
else
    usage
    exit 0
fi
