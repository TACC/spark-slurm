#!/bin/bash
#
# Jupyter directories	- https://jupyter.readthedocs.io/en/latest/use/jupyter-directories.html
# Jupyter+spark+queue	- https://researchcomputing.princeton.edu/faq/spark-via-slurm
# Jupyter spark kernel	- https://tlortz.github.io/2018/08/13/spark-jupyter-on-mac/
# 
# vis portal files	- /home1/00832/envision/tacc-tvp/server/scripts/stampede2/jupyter/

###################################
# Helper functions
###################################
PROG=$(basename $0)
function ee { echo -e "[ERROR] $PROG: $@" >&2; exit 1; }
function ei { echo -e "[INFO] $PROG: $@" >&2; }
function ed { [ -n "$TACC_SPARK_VERBOSE" ] && echo -e "[DEBUG] $PROG: $@" >&2; }
function ew { echo -e "[WARN] $PROG: $@" >&2; }
export -f ee ei ed ew
###################################
# Load ENV
###################################
EF=/tmp/spark_env.txt
[ ! -e $EF ] && ee "Did not detect $EF. Was spark started by tacc-spark.sh?"
EFS="$(xargs <$EF)"
export $EFS
ed "Loaded from $EF: $EFS"

NODE_HOSTNAME=`hostname -s`
ei "running on node $NODE_HOSTNAME"
ed "unloading xalt"; module unload xalt

TACC_RUNTIME=`squeue -l -j $SLURM_JOB_ID | grep $SLURM_QUEUE | awk '{print $7}'` # squeue returns HH:MM:SS
if [ x"$TACC_RUNTIME" == "x" ]; then
	TACC_Q_RUNTIME=`sinfo -p $SLURM_QUEUE | grep -m 1 $SLURM_QUEUE | awk '{print $3}'`
	if [ x"$TACC_Q_RUNTIME" != "x" ]; then
		# pnav: this assumes format hh:dd:ss, will convert to seconds below
		#       if days are specified, this won't work
		TACC_RUNTIME=$TACC_Q_RUNTIME
	fi
fi

if [ "x$TACC_RUNTIME" != "x" ]; then
  # there's a runtime limit, so warn the user when the session will die
  # give 5 minute warning for runtimes > 5 minutes
        H=`echo $TACC_RUNTIME | awk -F: '{print $1}'` 
        M=`echo $TACC_RUNTIME | awk -F: '{print $2}'` 
        S=`echo $TACC_RUNTIME | awk -F: '{print $3}'`
        if [ "x$S" != "x" ]; then
            # full HH:MM:SS present
            H=$(($H * 3600)) 
            M=$(($M * 60))
            TACC_RUNTIME_SEC=$(($H + $M + $S))
        elif [ "x$M" != "x" ]; then
            # only HH:MM present, treat as MM:SS
            H=$(($H * 60))
            TACC_RUNTIME_SEC=$(($H + $M))
        else 
            TACC_RUNTIME_SEC=$S
        fi
fi

###################################
# Detect Jupyter
###################################
export IPYTHON_BIN=$(which jupyter)
if [ "x$IPYTHON_BIN" == "x" ]; then
  ei "Loaded modules below"; module list
  ee "Could not find jupyter install"
fi
if `echo $IPYTHON_BIN | grep -qve '^/opt'` ; then
  ew "non-system python detected. Script may not behave as expected"
fi
ed "Using jupyter binary $IPYTHON_BIN"
export PYSPARK_DRIVER_PYTHON=$IPYTHON_BIN

###################################
# Jupyter config
###################################
export NB_SERVERDIR=$HOME/.jupyter
export JUPYTER_LOGFILE=$NB_SERVERDIR/${NODE_HOSTNAME}.log
mkdir -p $NB_SERVERDIR
# remove old files
rm -f $NB_SERVERDIR/.jupyter_{address,port,status,job_id,job_start,job_duration,lock}

# Load the PySpark shell.py script when ./pyspark is used interactively:
export OLD_PYTHONSTARTUP="$PYTHONSTARTUP"
export PYTHONSTARTUP="${SPARK_HOME}/python/pyspark/shell.py"

export IPYTHON_ARGS="notebook --no-browser --config=$SPARK_HOME/jupyter/jupyter.spark.config.py"
export PYSPARK_DRIVER_PYTHON_OPTS="$IPYTHON_ARGS"

export PYTHONPATH=${SPARK_HOME}/jupyter/lib/python${TACC_PYTHON_VER}/site-packages:${PYTHONPATH}

LOCAL_IPY_PORT=5902
IPY_PORT_PREFIX=2

###################################
# Launch Jupyter
###################################
MURL="spark://${HOSTNAME}:${SPARK_MASTER_PORT}"
ei "Submitting jupyter process to spark and logging to $JUPYTER_LOGFILE"
# Tell tacc-submit.sh that this is a pyspark notebook
export JUPYTER_NOTEBOOK=1
nohup tacc-submit.sh --master $MURL &> $JUPYTER_LOGFILE && rm $NB_SERVERDIR/.jupyter_lock &

export IPYTHON_PID=$!
echo "$NODE_HOSTNAME $IPYTHON_PID" > $NB_SERVERDIR/.jupyter_lock
sleep 30

JUPYTER_TOKEN=`grep -m 1 'token=' $JUPYTER_LOGFILE | cut -d'?' -f 2`
ei "jupyter notebook launched at $(date)"

###################################
# Compute port and forward
###################################
# mapping uses node number then rack number for mapping
LOGIN_IPY_PORT=`echo $NODE_HOSTNAME | perl -ne 'print (($2+1).$3.$1) if /c\d(\d\d)-(\d)(\d\d)/;'`
if `echo ${NODE_HOSTNAME} | grep -q c5`; then 
    # on a c500 node, bump the login port 
    LOGIN_IPY_PORT=$(($LOGIN_IPY_PORT + 400))
fi
# use the ranges 32000 - 43499 for stampede2 
# add 22000 offset to computed login port
LOGIN_IPY_PORT=$(($LOGIN_IPY_PORT + 22000))
ed "TACC: got login node jupyter port $LOGIN_IPY_PORT"
# create reverse tunnel port to login nodes.  Make one tunnel for each login so the user can just
# connect to stampede2.tacc
for i in `seq 4`; do
    ssh -q -f -g -N -R $LOGIN_IPY_PORT:$NODE_HOSTNAME:$LOCAL_IPY_PORT login$i
done
ed "created reverse ports on all Stampede2 logins"

###################################
# Print/Email portal info
###################################
msg="Your jupyter notebook server is now running! Please point your favorite web browser to:\n\n  https://vis.tacc.utexas.edu:$LOGIN_IPY_PORT/?$JUPYTER_TOKEN\n"
ei "$msg"
if [[ $1 == *@* ]]; then
	ed "Sending notebook URL to $1"
	echo -e "$msg" | mailx -s "Jupyter notebook now running" $1
fi

# info for TACC Visualization Portal
echo "vis.tacc.utexas.edu" > $NB_SERVERDIR/.jupyter_address
echo "$LOGIN_IPY_PORT/?$JUPYTER_TOKEN" > $NB_SERVERDIR/.jupyter_port
echo "$SLURM_JOB_ID" > $NB_SERVERDIR/.jupyter_job_id
# write job start time and duration (in seconds) to file
date +%s > $NB_SERVERDIR/.jupyter_job_start
echo "$TACC_RUNTIME_SEC" > $NB_SERVERDIR/.jupyter_job_duration
sleep 1
echo "success" > $NB_SERVERDIR/.jupyter_status

###################################
# Handle shutdown
###################################
# spin on .jupyter_lockfile to keep job alive
while [ -f $NB_SERVERDIR/.jupyter_lock ]; do
  sleep 10
done
ed "Jupyter was quit in browser"

ed "Stopping port forwarding"
pkill -9 -f "ssh -q -f -g -N -R $LOGIN_IPY_PORT"

# Job is done! Wait a brief moment so ipython can clean up after itself
sleep 1

ei "job $SLURM_JOB_ID execution finished at: `date`"
