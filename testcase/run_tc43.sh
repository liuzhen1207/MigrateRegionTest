for i in {1..30}
do
sh -x tc43_add_peer_stop_cn_coord.sh> iot_tc43_${i}.out 2>&1
sleep 3
v_empty_set_num=$(/data1/iotdb/resdb/v2082rc1_0131_e9b141f/sbin/start-cli.sh -h 172.20.70.3 -e "select  commitID,tc_name,tc_elapsed_time,tc_result,warnMsg  from root.autotest.ip4 where commitID='v20101_rc7_0624_ae72650' and tc_name='tc43_add_peer_stop_cn_coord.sh' and time>= now()-60000 and tc_result=false;"|grep "Empty set"|wc -l)

if [[ ${v_empty_set_num} = 0 ]];then
echo "reproduced."
break
fi
sleep 10
done
