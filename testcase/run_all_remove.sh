#!/bin/bash
desc=`cat ../conf/test.conf |grep "v_cur_db="|awk -F '=' '{print $2}'`
mkdir ${desc}
i=1
v_cur_time=`date +'%Y_%m_%d_%H_%M_%S'`
#for i in {1..5}
#do
exec 3<./testcase_ok_list.txt
while read line <&3
do
v_cur_time=`date +'%Y_%m_%d_%H_%M_%S'`
v_tc=`echo ${line}|awk -F '.' '{print $1}'`
   sh -x ${line} > ./${desc}/${v_tc}_${v_cur_time}.out 2>&1
sleep 60
done
#done
