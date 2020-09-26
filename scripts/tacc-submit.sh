#!/usr/bin/env bash

# Written by Greg Zynda (gzynda@tacc.utexas.edu)

###################################
# Helper functions
###################################
PROG=$(basename $0)
function ee {
	echo "[ERROR] $PROG: $@" >&2; exit 1
}
function ei {
	echo "[INFO] $PROG: $@" >&2;
}
function ed {
	[ -n "$TACC_SPARK_VERBOSE" ] && echo "[DEBUG] $PROG: $@" >&2;
}
function ew {
	echo "[WARN] $PROG: $@" >&2;
}
export -f ee ei ed ew

###################################
# Load ENV
###################################
EF=/tmp/spark_env.txt
[ ! -e $EF ] && ee "Did not detect $EF. Was spark started by tacc-spark.sh?"
EFS="$(xargs <$EF)"
export $EFS
ed "Loaded from $EF: $EFS"

###################################
# Calculate cores for driver
###################################
CORES=$(cpuinfo -c | grep L1 | grep -o "([^)]\+)" | head -n $CORES_PER_TASK | tail -n +$(( $ORCH_CORES+1 )) | tr -d '\n' | sed -e 's/)(/,/g' -e 's/[)(]//g' -e 's/$/\n/')
ei "Driver will run on $(( $CORES_PER_TASK-$ORCH_CORES )) cores: $CORES"

###################################
# Set spark variables
###################################
export MALLOC_ARENA_MAX=1
ed "Each JVM will use $MALLOC_ARENA_MAX memory pool(s)"
export SPARK_DAEMON_JAVA_OPTS="-XX:+UseParallelOldGC -XX:ParallelGCThreads=${GC:-2}"
ed "Each JVM will have ${GC:-2} GC threads"
export PYSPARK_PYTHON=$TACC_FAMILY_PYTHON
ed "Pyspark will use $PYSPARK_PYTHON"

###################################
# Launch the driver
###################################
if [ "$SLURM_JOB_PARTITION" == "flat-quadrant" ]; then
	# Get MCDRAM availability
	#FREEMEM=$(numactl -H | grep "1 free" | awk '{print $4}')
	export SPARK_DAEMON_MEMORY=$(( 16*1000*$FREE_P/100 ))m
	ed "Driver is allocated $SPARK_DAEMON_MEMORY memory in MCDRAM"
	NUMA_ARGS="--membind=1 --physcpubind=$CORES"
else
	export SPARK_DAEMON_MEMORY=$(( DRIVERPAD*1000*$FREE_P/100 ))m
	ed "Driver is allocated $SPARK_DAEMON_MEMORY memory"
	NUMA_ARGS="--physcpubind=$CORES"
fi

# Needs to be set to driver limits
WM=$(( $worker_mem_mb - $DAEMON_MEM ))
# Fails when this is uncommented
#export SPARK_WORKER_MEMORY=${WM}m

DM="--driver-memory $SPARK_DAEMON_MEMORY"
EM="--executor-memory $(( $WM/$SPARK_WORKER_CORES ))m"
#EC="--total-executor-cores "

if [ "$JUPYTER_NOTEBOOK" == "1" ]; then
	ed "Submitting pyspark-shell for jupyter notebook"
	ed "numactl $NUMA_ARGS $SPARK_HOME/bin/spark-submit pyspark-shell-main \
		--name \"PySparkShell\" $DM $EM \"$@\""
	numactl $NUMA_ARGS $SPARK_HOME/bin/spark-submit pyspark-shell-main \
		--name "PySparkShell" $DM $EM "$@"
else
	ed "numactl $NUMA_ARGS $SPARK_HOME/bin/spark-submit $DM $EM $@"
	numactl $NUMA_ARGS $SPARK_HOME/bin/spark-submit $DM $EM $@
fi
