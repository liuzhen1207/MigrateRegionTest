for i in {1..20}
do
sh -x tc31_mig_sr_create_ts.sh > iot_tc31_${i}.out 2>&1
v_ok=`grep "sh : pass" iot_tc31_${i}.out |wc -l`
if [[ ${v_ok} = 0 ]];then
echo "fail"
break
fi

done
