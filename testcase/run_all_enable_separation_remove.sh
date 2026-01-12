#!/bin/bash
i=1
v_cur_time=`date +'%Y_%m_%d_%H_%M_%S'`
v_cur_time1=`date +%s`
res_file="test_enable_separation_remove_${v_cur_time}.out"
exec 3<./enable_separation_remove_list.txt
while read line <&3
do
   sh -x ${line} >> ./${res_file}
done

v_cur_time2=`date +%s`
v_elp=$((v_cur_time2-v_cur_time1))
echo "test time:${v_elp)) sec."
