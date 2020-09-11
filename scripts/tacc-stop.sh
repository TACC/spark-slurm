#!/usr/bin/env bash

###################################
# Handle CLI arguments
###################################
function usage {
	echo """Stops all spark processes.

Usage $(basename $0) [-h] [-f]

optional arguments:
 -f     Force kill java processes
 -h     Display help""" >&2; exit 0
}

while getopts :hf flag; do
	case "${flag}" in
		f) FORCE=1;;
		:) echo -e "[ERROR] Missing an argument for ${OPTARG}\n" >&2; usage;;
		\?) echo -e "[ERROR] Illegal option ${OPTARG}\n" >&2; usage;;
		h) usage;;
	esac
done

###################################
# Load the config
###################################
. "${SPARK_HOME}/sbin/spark-config.sh" 
. "${SPARK_HOME}/bin/load-spark-env.sh"

###################################
# Stop daemons
###################################
SPARK_DAEMON=${SPARK_HOME}/sbin/spark-daemon.sh
echo "Stopping the main process:"
$SPARK_DAEMON stop org.apache.spark.deploy.master.Master 1 | uniq -c

echo -e "\nStopping the worker processes:"
# TODO change to tasks-1
CLASS=org.apache.spark.deploy.worker.Worker
srun bash -c "export HOSTNAME=\$(hostname); [ \"\$SLURM_PROCID\" -gt \"0\" ] && \
	$SPARK_DAEMON stop $CLASS \$(( \$SLURM_LOCALID + 1 )) || exit 0" | sort | uniq -c
###################################
# Kill java
###################################
if [ -n "$FORCE" ]; then
	echo "Halting all java processes" >&2
	srun -N $SLURM_NNODES -n $SLURM_NNODES pkill -9 java 2>/dev/null
fi
rm -f /tmp/spark_{ibrun.log,env.txt}
