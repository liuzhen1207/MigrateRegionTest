for i in {4..20}
do
sh -x tc58_load_mig_iot_tree_table.sh > v2031rc1_iot_${i}.out 2>&1
v_ok=`grep "sh : pass" v2031rc1_iot_${i}.out |wc -l`
if [[ ${v_ok} = 0 ]];then
echo "fail"
break
fi

done
