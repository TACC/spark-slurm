#!/bin/bash

###################################
# Helper functions
###################################
PROG=$(basename $0)
function ee { echo "[ERROR] $PROG: $@" >&2; exit 1; }
function ei { echo "[INFO] $PROG: $@" >&2; }
function ed { [ -n "$TACC_SPARK_VERBOSE" ] && echo "[DEBUG] $PROG: $@" >&2; }
function ew { echo "[WARN] $PROG: $@" >&2; }
export -f ee ei ed ew
###################################
# Default values
###################################
export QUEUE=skx-dev
export NODES=1
export PYTHON=3
export HOURS=2
###################################
# Handle CLI arguments
###################################
function usage {
	echo """Submits a distributed jupyter pyspark job to slurm.

Usage: $PROG [-h] [-e STR] [-q STR] [-N INT] [-H INT] [-p INT]
             [-A STR] [-v] [-f]

optional arguments:
 -e STR Email to send notebook URL to (required)
 -A STR Allocation to charge against (required)
 -q STR Queue job is submitted to [$QUEUE]
 -N INT Number of nodes to use [$NODES]
 -H INT Number of hours for job [$HOURS]
 -p INT Major python version (2|3) [$PYTHON]
 -f     Submit job without prompting
 -v     Enable verbose logging

The job will also stop once you \"Quit\" the notebook server. 
""" >&2; exit 0
}
while getopts :e:A:q:N:H:p:hfv flag; do
	case "${flag}" in
		e) export EMAIL=${OPTARG};;
		A) export ALLOC=${OPTARG};;
		q) export QUEUE=${OPTARG};;
		N) export NODES=${OPTARG};;
		H) export HOURS=${OPTARG};;
		p) export PYTHON=${OPTARG};;
		f) FORCE=1;;
		v) export TACC_SPARK_VERBOSE=1;;
		:) echo -e "[ERROR] Missing an argument for ${OPTARG}\n" >&2; usage;;
		\?) echo -e "[ERROR] Illegal option ${OPTARG}\n" >&2; usage;;
		h) usage;;
	esac
done
export HOURS=$(printf "%02i\n" $HOURS)

if [[ $EMAIL != *@*\.* ]]; then
	ee "Not a valid email: $EMAIL"
fi
if [ -z "$ALLOC" ]; then
	ee "Please specify an allocation"
fi

# Compute tasks
case "${TACC_SYSTEM}-${QUEUE}" in
	stampede2-flat-quadrant) TASKS=$(( 34*$NODES ));;
	stampede2-normal) TASKS=$(( 34*$NODES ));;
	stampede2-development) TASKS=$(( 34*$NODES ));;
	stampede2-skx-dev) TASKS=$(( 24*$NODES ));;
	stampede2-skx-normal) TASKS=$(( 24*$NODES ));;
	*) ee "Unhandled queue ${QUEUE}";;
esac
export TASKS
###################################
# Build job command
###################################
SUFF=$(date +%y%m%d%H%M%S)
JOB=spark_jupyter_${SUFF}.sbatch
TEMPLATE=${JUPYTER_PATH}/sbatch.template
GEN="envsubst '\$EMAIL \$QUEUE \$NODES \$TASKS \$HOURS \$PYTHON \$ALLOC' < $TEMPLATE > $JOB && ed \"Created $JOB\""
###################################
# Confirm and submit
###################################
if  [ -n "$FORCE" ]; then
	eval $GEN && sbatch $JOB
else
read -p """This will submit a jupyter+spark job with the following parameters:

 - $QUEUE queue
 - $NODES nodes
 - $HOURS hours
 - python$PYTHON

Continue (y/n)? """ -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		eval $GEN && sbatch $JOB
	else
		ei "Cancelling job submission"
	fi
fi

