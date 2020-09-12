#!/bin/bash

function get_sec {
	#{ grep "$1" $2 || echo "= NA sec"; } | tee >(cat 1>&2) | grep -oE "= [0-9\.NA]+ sec" | cut -f 2 -d ' '
	{ grep "$1" $2 || echo "= NA sec"; } | grep -oE "= [0-9\.NA]+ sec" | cut -f 2 -d ' '
}
export -f get_sec

echo "File,Workers,Threads,Group By,Repartition,Inner Join,Broadcast Inner Join"
for f in $(/bin/ls *workers*shuffle.log); do
	T=${f%%threads*}
	T=${T##*workers_}
	W=${f%%workers*}
	# Parsing
	GB=$(get_sec "Group By test time" $f)
	R=$(get_sec "Repartition test time" $f)
	IJ=$(get_sec "Inner join test time" $f)
	BIJ=$(get_sec "Broadcast inner join time" $f)
	echo "$f,$W,$T,$GB,$R,$IJ,$BIJ"
done
echo
echo "File,Workers,Threads,SHA-512,Pi,Pi DataFrame"
for f in $(/bin/ls *workers*cpu.log); do
	T=${f%%threads*}
	T=${T##*workers_}
	W=${f%%workers*}
	# Parsing
	SHA=$(get_sec "SHA-512 benchmark" $f)
	PI=$(get_sec "Calculate Pi benchmark  " $f)
	PIDF=$(get_sec "Calculate Pi benchmark using" $f)
	echo "$f,$W,$T,$SHA,$PI,$PIDF"
done
exit

34workers_68threads_cpu.log:20/09/11 11:50:05 INFO __main__: SHA-512 benchmark time                 = 284.704449144
19204 seconds for 200,000,000 hashes
34workers_68threads_cpu.log:20/09/11 11:50:05 INFO __main__: Calculate Pi benchmark                 = 261.508430227
6373 seconds with pi = 3.1415519824, samples = 2,500,000,000
34workers_68threads_cpu.log:20/09/11 11:50:05 INFO __main__: Calculate Pi benchmark using dataframe = 24.7404244663
19382 seconds with pi = 3.1415849104, samples = 2,500,000,000
34workers_68threads_shuffle.log:20/09/11 11:38:56 INFO __main__: Group By test time         = 209.6065014572814 sec
onds
34workers_68threads_shuffle.log:20/09/11 11:38:56 INFO __main__: Repartition test time      = 221.7853749813512 sec
onds (1450 partitions)
34workers_68threads_shuffle.log:20/09/11 11:38:56 INFO __main__: Inner join test time       = 340.7187526207417 sec
onds 
34workers_68threads_shuffle.log:20/09/11 11:38:56 INFO __main__: Broadcast inner join time  = 241.67136968299747 se
conds 

