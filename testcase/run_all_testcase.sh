#!/bin/bash
i=1
v_cur_time=`date +'%Y_%m_%d_%H_%M_%S'`
res_file="test_log_${v_cur_time}.out"
exec 3<./tc_list.txt
while read line <&3
do
   sh -x ${line} >> ./${res_file}
done
set_sys_conf ${line} ${db_dir} ".*dn_thrift_max_frame_size=.*" "dn_thrift_max_frame_size=134217728"
