#!/bin/bash
#sleep 3600
i=1
v_cur_time=`date +'%Y_%m_%d_%H_%M_%S'`
v_cur_time1=`date +%s`
res_file="v1361rc2_${v_cur_time}.out"
exec 3<./rm_dn_v13_testlist.txt
while read line <&3
do
v_tc=`echo ${line}|awk -F '_' '{print $1}'`
   sh -x ${line} > ./${v_tc}_res.out 2>&1
done

v_cur_time2=`date +%s`
v_elp=$((v_cur_time2-v_cur_time1))
echo "test time:${v_elp} sec."
