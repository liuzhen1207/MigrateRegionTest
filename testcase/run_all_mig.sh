#!/bin/bash
#while true
#do
#   v_ok=`ps -ef|grep sh|grep tc2025_issue0097.sh|wc -l`
#   if [[ ${v_ok} -lt 2 ]];then
#      break
#   else
#      sleep 5m
#   fi
#done
desc=`cat ../conf/test.conf |grep "v_cur_db="|awk -F '=' '{print $2}'`
mkdir ${desc}
i=1
v_cur_time=`date +'%Y_%m_%d_%H_%M_%S'`
res_file="test_mig_${v_cur_time}.out"
exec 3<./migrate_testcase_list.txt
while read line <&3
do
v_tc=`echo ${line}|awk -F '_' '{print $1}'`
   sh -x ${line} > ./${desc}/${v_tc}_res.out 2>&1
done

v_cur_time=`date +'%Y_%m_%d_%H_%M_%S'`
res_file="test_mig_${v_cur_time}.out"
exec 3<./remove_iotv1_testcase_list.txt
while read line <&3
do
v_tc=`echo ${line}|awk -F '_' '{print $1}'`
   sh -x ${line} > ./${desc}/${v_tc}_res.out 2>&1 
done
