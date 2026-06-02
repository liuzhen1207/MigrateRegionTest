#!/bin/bash
t=`date +"%Y_%m_%d_%H_%M_%S"`
nohup ./benchmark.sh -cf remove/tree_aligned > ${t}_tree_algined.out &
sleep 5
nohup ./benchmark.sh -cf remove/tree_nonaligned > ${t}_tree_nonalgined.out &
nohup ./benchmark.sh -cf remove/tree_aligned_temp > ${t}_tree_algined_temp.out &
nohup ./benchmark.sh -cf remove/table > ${t}_table.out &

