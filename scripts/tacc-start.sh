#!/usr/bin/env bash

# Written by Greg Zynda (gzynda@tacc.utexas.edu)

###################################
# Sources of inspiration
###################################
# https://cug.org/proceedings/cug2017_proceedings/includes/files/tut110s2-file1.pdf
# https://www.dursi.ca/post/spark-in-hpc-clusters.html

# spark raspi https://dev.to/awwsmm/building-a-raspberry-pi-hadoop-spark-cluster-8b2
# srun affinity https://slurm.schedmd.com/mc_support.html#srun_highlevelmc

# spark config
# standalone https://spark.apache.org/docs/3.0.0/spark-standalone.html
# installing https://spark.apache.org/docs/3.0.0/building-spark.html
# configure  https://spark.apache.org/docs/3.0.0/configuration.html
# tuning     https://spark.apache.org/docs/3.0.0/tuning.html
# IBM        https://www.ibm.com/support/knowledgecenter/en/SSCTFE_1.1.0/com.ibm.azk.v1r1.azka100/topics/azkic_r_memcpuconfigopts.htm

# benchmark  https://diybigdata.net/2020/01/pyspark-benchmark/

###################################
# Helper functions
###################################
PROG=$(basename $0)
function min {
	echo $(( $1 < $2 ? $1 : $2 ))
}
function max {
	echo $(( $1 > $2 ? $1 : $2 ))
}
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
# Calculate resources
###################################
# Tasks
TASKS_PER_NODE=$(echo ${SLURM_TASKS_PER_NODE:-1} | grep -o -m 1 "^[0-9]\+")
CORES_PER_NODE=$(cpuinfo -g | grep -m 1 Cores | awk '{print $3}')
THREADS_PER_CORE=$(cpuinfo -g | grep "per core" | awk '{print $5}')
THREADS_PER_NODE=$(( $CORES_PER_NODE*$THREADS_PER_CORE ))
CORES_PER_TASK=$(( $CORES_PER_NODE/$TASKS_PER_NODE ))
THREADS_PER_TASK=$(( $CORES_PER_NODE/$TASKS_PER_NODE ))

# Memory
if [ "$SLURM_JOB_PARTITION" == "flat-quadrant" ]; then
	# Get DDR availability, not MCDRAM
	FREEMEM=$(numactl -H | grep "0 size" | awk '{print $4}')
	DRIVERPAD=0
else
	FREEMEM=$(free -m | grep Mem | awk '{print $2}')
	DRIVERPAD=16
fi
# Percent of free memory to use
FREE_P=90
# Set memory to use for orchestrator process
ODM=1
OWM=2

###################################
# Handle CLI arguments
###################################
function usage {
	echo """Launches a distributed spark instance on TACC infrastructure.

Usage: $PROG [-h] [-c INT] [-d INT] [-p INT] [-m INT]
  [-w INT] [-g INT] [-r] [-v]

optional arguments:
 -c INT Number of cores per worker task (-n) [$THREADS_PER_TASK]
 -d INT Reserved memory for driver in GB [$DRIVERPAD] (not 
        used on flat-quadrant)
 -p INT Percent of available memory to use [$FREE_P]
 -m INT Orchestrator port [7077]
 -w INT Orchestrator WebUI port [8077]
 -g INT Number of garbage collector threads [2]
 -r     Enable monitoring with remora
 -v     Enable verbose logging

This should be run from inside a job. By default, it will automatically 
set (-c) to saturate all physical cores on each node in the job.

$ idev -N 2 -n 64
$ module load spark
$ $PROG

Process:
  - Reserves the first slot for orchestrator and driver
  - Launches the orchestrator on the first core with $ODM GB of reserved memory
  - Launches 63 workers across the 2 nodes, with each task using 2 cores

The spark instance can be shut down with tacc-stop.sh""" >&2; exit 0
}
while getopts :hc:d:p:m:w:g:rv flag; do
	case "${flag}" in
		c) SPARK_WORKER_CORES=${OPTARG};;
		d) DRIVERPAD=${OPTARG};;
		p) FREE_P=${OPTARG};;
		m) SPARK_MASTER_PORT=${OPTARG};;
		w) SPARK_MASTER_WEBUI_PORT=${OPTARG};;
		g) GC=${OPTARG};;
		r) MONITOR=1;;
		v) TACC_SPARK_VERBOSE=1;;
		:) echo -e "[ERROR] Missing an argument for ${OPTARG}\n" >&2; usage;;
		\?) echo -e "[ERROR] Illegal option ${OPTARG}\n" >&2; usage;;
		h) usage;;
	esac
done

if [ "$SLURM_JOB_ID" == "" ]; then
	ee "Please only run on a compute node"
fi
[ "$SLURM_NTASKS" -lt "2" ] && ee "Please run with at least 2 tasks"

###################################
# Calculate resource limits
###################################
# Calculate worker memory
ed "Detected $(( $FREEMEM/1000 )) GB of free memory"
TASK_MEM=$(( FREEMEM*$FREE_P/100/$TASKS_PER_NODE ))
FREE_M_DRIVER=$FREEMEM
if [ "$TASK_MEM" -lt "2000" ]; then
	ed "Reserving $OWM GB for the orchestrator."
	FREE_M_DRIVER=$(( $FREEMEM-($OWM*1000) ))
fi
if [ "$SLURM_JOB_PARTITION" != "flat-quadrant" ]; then
	ed "Reserving $DRIVERPAD GB for the driver."
	FREE_M_DRIVER=$(( $FREE_M_DRIVER-($DRIVERPAD*1000) ))
fi
FREE_M_OVERHEAD=$(( $FREE_M_DRIVER*$FREE_P/100 ))
worker_mem_mb=$(( $FREE_M_OVERHEAD/$TASKS_PER_NODE ))
ed "Using ${FREE_P}% of available memory ($(( $FREE_M_OVERHEAD/1000 )) GB). Each worker will have $worker_mem_mb MB of memory."

###################################
# Set spark variables
###################################
# Load the configuration
. ${SPARK_HOME}/sbin/spark-config.sh
. ${SPARK_HOME}/bin/load-spark-env.sh
ed "Loaded default spark config and environment"
# Daemon shortcut
SPARK_DAEMON=${SPARK_HOME}/sbin/spark-daemon.sh
# Set the python
export PYSPARK_PYTHON=$TACC_FAMILY_PYTHON
ed "Pyspark will use $PYSPARK_PYTHON"
# Ports and URLs
export SPARK_MASTER_HOST="`hostname -f`"
export SPARK_MASTER_PORT=${SPARK_MASTER_PORT:-7077}
export SPARK_MASTER_WEBUI_PORT=${SPARK_MASTER_WEBUI_PORT:-8077}
export SPARK_MASTER_URL="spark://${SPARK_MASTER_HOST}:${SPARK_MASTER_PORT}"

# Unless specified otherwise, match to cores
export SPARK_WORKER_CORES=${SPARK_WORKER_CORES:-$THREADS_PER_TASK}
ed "Each worker will spawn $SPARK_WORKER_CORES executor processes"
# Set the number the memory pools - https://stackoverflow.com/questions/561245/virtual-memory-usage-from-java-under-linux-too-much-memory-used
#export MALLOC_ARENA_MAX=$SPARK_EXECUTOR_THREADS
export MALLOC_ARENA_MAX=1
ed "Each JVM will use $MALLOC_ARENA_MAX memory pool(s)"

###################################
# Calculate orchestrator cores
###################################
[ "$CORES_PER_TASK" -lt "2" ] && ee "Please use at least 2 cores per task"
# ORCH only gets 1 core
ORCH_CORES=1
CORES=$(cpuinfo -c | grep L1 | grep -o "([^)]\+)" | head -n $ORCH_CORES | tr -d '\n' | sed -e 's/)(/,/g' -e 's/[)(]//g' -e 's/$/\n/')

###################################
# Start the orchestrator
###################################
CLASS="org.apache.spark.deploy.master.Master"
# SPARK_DAEMON_MEMORY	Memory to allocate to the Spark master and worker daemons (default: 1g)
# SPARK_WORKER_MEMORY	Total amount of memory to allow Spark applications to use on the machine, e.g. 1000m, 2g (default: total memory minus 1 GiB); note that each application's individual memory is configured using its spark.executor.memory property.
export SPARK_DAEMON_JAVA_OPTS="-XX:+UseParallelOldGC -XX:ParallelGCThreads=${GC:-2}"
ed "Each JVM will have ${GC:-2} GC threads"


	#echo "Starting MAIN process on MCDRAM with $SPARK_DAEMON_MEMORY allocated on $ORCH_CORES cores"
	#numactl --membind=1 --physcpubind=$CORES $SPARK_DAEMON start $CLASS 1 \
	#	--host $SPARK_MASTER_HOST --port $SPARK_MASTER_PORT --webui-port $SPARK_MASTER_WEBUI_PORT
export SPARK_DAEMON_MEMORY=${ODM}g
export SPARK_WORKER_MEMORY=${OWM}g
ei "Starting MAIN orchestrator process with $SPARK_DAEMON_MEMORY allocated on $ORCH_CORES cores: $CORES"
numactl --physcpubind=$CORES $SPARK_DAEMON start $CLASS 1 --host $SPARK_MASTER_HOST \
	--port $SPARK_MASTER_PORT --webui-port $SPARK_MASTER_WEBUI_PORT
ei "Spark orchestrator is listening on $SPARK_MASTER_URL"

###################################
# Start the workers
###################################
CLASS="org.apache.spark.deploy.worker.Worker"
CALC=$(( $worker_mem_mb / ($SPARK_WORKER_CORES+1) ))
DAEMON_MEM=$(max 768 $CALC)
export SPARK_DAEMON_MEMORY=${DAEMON_MEM}m
export SPARK_WORKER_MEMORY=$(( $worker_mem_mb - $DAEMON_MEM ))m
#export SPARK_DAEMON_MEMORY=$(( $worker_mem_mb / $SPARK_WORKER_CORES ))m

# Start the workers
ei "Starting $(( $SLURM_NTASKS-1 )) workers across $SLURM_NNODES nodes."
ed "Each worker will be allocated $SPARK_DAEMON_MEMORY for their JVM and $SPARK_WORKER_MEMORY of memory for their $SPARK_WORKER_CORES executors."

# Determine desired worker port
SPARK_WORKER_WEBUI_PORT=${SPARK_WORKER_WEBUI_PORT:-8081}
if [ "$SPARK_WORKER_PORT" != "" ]; then
	PORT_ARG="--port \$(( $SPARK_WORKER_PORT + \$MPI_LOCALRANKID - 1 ))"
fi

# Enable monitoring
if [ "$MONITOR" != "" ]; then
	module load remora
	echo "Monitoring workers with remora"
	REMORA='remora'
fi

#TODO update this to skip the first task
$REMORA ibrun bash -c "export HOSTNAME=\$(hostname); [ \"\$PMI_RANK\" -gt \"0\" ] && \
	$SPARK_DAEMON start $CLASS \$(( \$MPI_LOCALRANKID+1 )) \
	--webui-port \$(( 8081+\$MPI_LOCALRANKID+1 )) $PORT_ARG $SPARK_MASTER_URL || exit 0" > /tmp/spark_ibrun.log &
sleep 20
printf "%7i starting $CLASS, logging to $SPARK_LOG_DIR\n" $(grep -c "Worker" /tmp/spark_ibrun.log)

###################################
# Export variables
###################################
echo """worker_mem_mb=$worker_mem_mb
SPARK_WORKER_CORES=$SPARK_WORKER_CORES
DAEMON_MEM=$DAEMON_MEM
CORES_PER_TASK=$CORES_PER_TASK
ORCH_CORES=$ORCH_CORES
TACC_SPARK_VERBOSE=$TACC_SPARK_VERBOSE
DRIVERPAD=$DRIVERPAD
GC=${GC:-2}
FREE_P=$FREE_P""" > /tmp/spark_env.txt
ed "Wrote /tmp/spark_env.txt which is used by tacc-submit.sh"
