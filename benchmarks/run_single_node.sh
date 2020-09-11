#!/bin/bash
#SBATCH -J pyspark_bench
#SBATCH -o pyspark_bench.%j.o
#SBATCH -e pyspark_bench.%j.e
#SBATCH -p flat-quadrant
#SBATCH --mail-user=gzynda@tacc.utexas.edu
#SBATCH --mail-type=begin
#SBATCH --mail-type=end
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -t 04:00:00
#SBATCH -A SD2E-Community

ml spark/3.0.0 python3
CORES_PER_NODE=$(cpuinfo -g | grep -m 1 Cores | awk '{print $3}')

function spark-submit {
	# Start SPARK
	tacc-start.sh -v -c $(( ${THREADS}/${NWORKERS} ))
	echo "[BEFORE] java: $(pgrep -c java)  python: $(pgrep -c python)"
	tacc-submit.sh $@
	sleep 5
	echo "[AFTER] java: $(pgrep -c java)  python: $(pgrep -c python)"
	# Stop spark
	tacc-stop.sh -f
	sleep 2
}
MURL="--master spark://$HOSTNAME:7077"
export -f spark-submit


ROWS=200000000
SAMPLES=2500000000
#ROWS=10000000
#SAMPLES=250000000
PART=$(( 272*4 ))
NEW_PART=$(( $PART*4/3 ))

odata=data_${PART}
data=data_${SLURM_JOB_ID}
[ -e $data ] && rm -rf $data
cp -r $odata $data


for NWORKERS in ${NWORKERS:-$(($CORES_PER_NODE/2)) $(($CORES_PER_NODE/4)) 4}; do
	# Update env
	export SLURM_NTASKS=$NWORKERS
	export SLURM_TASKS_PER_NODE=$NWORKERS
	export SLURM_NPROCS=$NWORKERS
	export SLURM_TACC_CORES=$NWORKERS
	for THREADS in ${THREADS:-$(($CORES_PER_NODE/2)) $CORES_PER_NODE $(($CORES_PER_NODE*2))}; do
		echo "Running benchmark on $NWORKERS workers and $THREADS threads"
		log=$PWD/${NWORKERS}workers_${THREADS}threads
		echo "Starting with $(/bin/ls $data | wc -l) files"
		ls -lh $data | head
		# Generate data
		#spark-submit $MURL --name "gendata" generate-data.py \
		#	$data -r $ROWS -p $PART &> ${log}_gen.log
		# Shuffle data
		spark-submit $MURL --name "benchmark-shuffle" benchmark-shuffle.py \
			$data -r $NEW_PART &> ${log}_shuffle.log
		# Calculate pi
		spark-submit $MURL --name "benchmark-cpu" benchmark-cpu.py \
			$data -s $SAMPLES -p $PART &> ${log}_cpu.log
		echo "Ending with $(/bin/ls $data | wc -l) files"
		ls -lh $data | head
	done
done
rm -rf $data
