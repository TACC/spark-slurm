# Spark on TACC HPC

This work is meant to deploy a distributed [Apache Spark](https://spark.apache.org/) instance in a Slurm job at [TACC](https://www.tacc.utexas.edu/), run tasks in client mode, and then shut down.

The Spark framework is meant to be [configured](https://spark.apache.org/docs/latest/configuration.html) once for a system, and either run as shared service via [Hadoop's YARN](https://hadoop.apache.org/docs/current/hadoop-yarn/hadoop-yarn-site/YARN.html) manager or as a [standalone cluster](https://spark.apache.org/docs/latest/spark-standalone.html).
Since TACC already uses [Lustre](https://lustre.org/) for its shared filesystems, not hadoop, this spark deployment only supports running in standalone mode. 

- Workers are started via `ibrun` so 
The Spark framework is generally meant for 
Spark on TACC HPC

## Usage

### 1. Start a Slurm job

First, you'll need to start a compute job with either TACC's `idev` for *interactive* computing or `sbatch` for batch computing.
The Spark deployment will automatically scale to the resources allocated to your job, where each `-n` task will be evenly spread across the number of `-N` nodes you request.

For [KNL nodes](https://portal.tacc.utexas.edu/user-guides/stampede2#knl-compute-nodes), we reccommend

For standard (non-Phi) nodes, we recommend

### 2. Load modules

```
# Until permanent deployment
module use /work/03076/gzynda/public/apps/modulefiles

module load spark/3.0.1 python3
```

> We have tested pyspark with python3, but your code may work with python2


### 3. Start the Spark Cluster

Running `tacc-start.sh` will start the Spark cluster in your compute job by:

1. Starting the main orchestrator
   - Reserves 2GB of memory and
   - Restricted to the first core of the first task slot
   - Prints the spark://[host]:[port] url used for sumitting jobs
2. Reserving memory for the client driver
   - Reserve memory for the client process started by (tacc-submit.sh). This defaults to 16GB, but can be controlled with `-d` argument.
   - Will run on remaining cores of the first slot
3. Start the worker processes
   - Compute the number of executors per worker. Defaults to the number of physical cores per task, but can be configured with `-c` argument.
   - Evenly divides up the 90% of remaining memory between workers. The percentage can be controlled with the `-p` argument.
   - Starts workers across each node with `ibrun`
   - Workers are restriced to the cores of their task slot. This means that if there are two tasks on a four-core system, each task would have two cores.

> While spark does contain scripts for starting processes, we recommend using these since the java processes starve themselves of resources when they have access to every core on the system.

```
Launches a distributed spark instance on TACC infrastructure.

Usage: tacc-start.sh [-h] [-c INT] [-d INT] [-p INT] [-m INT]
  [-w INT] [-g INT] [-r] [-v]

optional arguments:
 -c INT Number of cores per worker task (-n) [28]
 -d INT Reserved memory for driver in GB [16] (not 
        used on flat-quadrant)
 -p INT Percent of available memory to use [90]
 -m INT Orchestrator port [7077]
 -w INT Orchestrator WebUI port [8077]
 -g INT Number of garbage collector threads [2]
 -r     Enable monitoring with remora
 -v     Enable verbose logging

This should be run from inside a job. By default, it will automatically 
set (-c) to saturate all physical cores on each node in the job.

$ idev -N 2 -n 64
$ module load spark
$ tacc-start.sh

Process:
  - Reserves the first slot for orchestrator and driver
  - Launches the orchestrator on the first core with 1 GB of reserved memory
  - Launches 63 workers across the 2 nodes, with each task using 2 cores

The spark instance can be shut down with tacc-stop.sh
```

### 4. Submit Spark jobs

Use the `tacc-submit.sh` to submit jobs to the spark cluster started in Step #3.

This script is meant to be used like `spark-submit`, except it automatically sets both the driver and executor memory based on your spark cluster configuration.
This also restricts the driver to N-1 processors from the first task, since the main orchestrator is on the first.

```
tacc-submit.sh --master spark://$HOSTNAME:7077 --name "job name" program.py argument1 argument2
```

### 5. Shutdown the Spark Cluster

Running `tacc-stop.sh` will stop all workers and the main orchestrator process.
Additionally, all java processes can be force halted and temporary files removed by including the `-f` flag.

```
Stops all spark processes.

Usage tacc-stop.sh [-h] [-f]

optional arguments:
 -f     Force kill java processes
 -h     Display help
```

## Benchmarks

This deployment was tested using [pyspark-benchmark](https://github.com/DIYBigData/pyspark-benchmark) to give an idea how it performed on different tasks.
We ran the benchmarks with the included [run_single_node.sh](benchmarks/run_single_node.sh) script
ROWS=200000000                                                                      
SAMPLES=2500000000                                                                  
#ROWS=10000000                                                                      
#SAMPLES=250000000                                                                  
PART=$(( 272*16 ))                                                                  
NEW_PART=$(( $PART*5/6 ))                                                           
                                                                                    
for NWORKERS in ${NWORKERS:-34 17 4}; do                                            
        # Update env                                                                
        export SLURM_NTASKS=$NWORKERS                                               
        export SLURM_TASKS_PER_NODE=$NWORKERS                                       
        export SLURM_NPROCS=$NWORKERS                                               
        export SLURM_TACC_CORES=$NWORKERS                                           
        for THREADS in ${THREADS:-34 68 136}; do                                    
                echo "Running benchmark on $NWORKERS workers and $THREADS threads"  
                log=$PWD/${NWORKERS}workers_${THREADS}threads                       
                data=/tmp/data_backup                                               
                #data=/tmp/${log}_data                                              
                rm -rf $data                                                        
                # Generate data                                                     
                #spark-submit $MURL --name "gendata" generate-data.py \             
                #       $data -r $ROWS -p $PART &> ${log}_gen.log                   
                tar -xf data_backup.tar -C /tmp                                     
                # Shuffle data                                                      
                spark-submit $MURL --name "benchmark-shuffle" benchmark-shuffle.py \
                        $data -r $NEW_PART &> ${log}_shuffle.log                    
                # Calculate pi                                                      
                spark-submit $MURL --name "benchmark-cpu" benchmark-cpu.py \        
                        $data -s $SAMPLES -p $PART &> ${log}_cpu.log                
                rm -rf $data                                                        
        done                                                                        
done                                                                                

### Single-Node Results

Data for the [pyspark-benchmark](https://github.com/DIYBigData/pyspark-benchmark) was generated as follows:

```
tacc-submit.sh --master spark://$HOSTNAME:7077 --name gendata generate-data.py data_backup -r 200000000 -p $(( 272*16 ))
```

<details><summary><b>KNL results - Shuffle</b></summary>

| Workers | Threads | Group By | Repartition | Inner Join | Broadcast Inner Join |
|---------|---------|:--------:|:-----------:|:----------:|:--------------------:|
|      17 |      34 |   221.7  |    331.6    |    488.6   |         339.6        |
|      17 |      68 |   220.1  |    221.6    |    372.3   |         262.3        |
|      34 |     136 |    NA    |      NA     |     NA     |          NA          |
|      34 |      34 |    NA    |      NA     |     NA     |          NA          |
|      34 |      68 |   208.5  |    217.2    |    356.7   |         240.1        |
|       4 |      34 |   377.2  |    461.5    |    633.0   |         459.1        |
|       4 |      68 |   318.4  |    313.1    |    778.4   |         370.3        |

</details>
<details><summary><b>KNL results - CPU</b></summary>

| Workers | Threads | SHA-512 |   Pi  | Pi DataFrame |
|---------|---------|:-------:|:-----:|:------------:|
|      17 |      34 |  352.2  | 510.6 |     36.8     |
|      17 |      68 |  298.6  | 272.1 |     29.6     |
|      34 |      34 |    NA   |   NA  |      NA      |
|      34 |      68 |  286.7  | 262.7 |     24.6     |
|       4 |      34 |  488.6  | 714.4 |     46.3     |
|       4 |      68 |  405.8  | 362.9 |     28.0     |

</details>
<details><summary><b>SKX results - Shuffle</b></summary>

| Workers | Threads | Group By | Repartition | Inner Join | Broadcast Inner Join |
|---------|---------|:--------:|:-----------:|:----------:|:--------------------:|
|      12 |      24 |   45.74  |    65.10    |    76.93   |         68.96        |
|      12 |      48 |   38.17  |    46.64    |    72.50   |         57.78        |
|      12 |      96 |   52.83  |    47.92    |    71.03   |         58.63        |
|      24 |      24 |   57.18  |    62.22    |    75.44   |         66.10        |
|      24 |      48 |   39.01  |    46.23    |    72.36   |         55.05        |
|      24 |      96 |   51.13  |    45.66    |    73.10   |         54.66        |
|       4 |      24 |   52.83  |    76.34    |    96.75   |         87.57        |
|       4 |      48 |   64.35  |    59.04    |    79.00   |         70.00        |
|       4 |      96 |    NA    |      NA     |     NA     |          NA          |

</details>
<details><summary><b>SKX results - CPU</b></summary>

| Workers | Threads | SHA-512 |   Pi  | Pi DataFrame |
|---------|---------|:-------:|:-----:|:------------:|
|      12 |      24 |  83.70  | 77.91 |     7.63     |
|      12 |      48 |  66.52  | 49.56 |     5.19     |
|      12 |      96 |  70.64  | 49.07 |     4.24     |
|      24 |      24 |  81.67  | 74.79 |     8.01     |
|      24 |      48 |  67.88  | 47.24 |     5.74     |
|      24 |      96 |  66.04  | 47.16 |     4.78     |
|       4 |      24 |  97.98  | 95.23 |     9.08     |
|       4 |      48 |  79.96  | 55.67 |     6.62     |
|       4 |      96 |  102.10 | 55.68 |     5.74     |

</details>


### Multi-Node

TODO

## Jupyter

TODO

## Troubleshooting

While TACC staff have done their best to tune this deployment, Spark was not designed for many-core systems and expects more memory than TACC nodes are designed with.

### Things to try

- Increase the number of parititions in your code
- Decrease the number of workers per node (decrease `-n`)
- Run on skylake instead of knl nodes
  - `skx-development` or `skx-normal` queues on S2
  - Skylake nodes have more memory per core and are much faster

### Submit an issue

Please [submit an issue](https://github.com/TACC/spark-slurm/issues/new/choose) if you are still encountering issues.
