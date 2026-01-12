#!/bin/bash
for i in {1..10}
do
sh -x tc1_v1361_2bm_remove_dn_20251112.sh > 1125_v1342rc4_tc${i}.out 2>&1 
sleep 3
done
