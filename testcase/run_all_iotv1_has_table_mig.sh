#!/bin/bash
i=1
v_cur_time=`date +'%Y_%m_%d_%H_%M_%S'`
res_file="test_iotv1_has_table_mig_${v_cur_time}.out"
exec 3<./IoTV1_has_table_migrate_testcase_list.txt
while read line <&3
do
   sh -x ${line} >> ./${res_file}
done
