for i in {1..10}
do
sh -x tc112_RMDN_no12_remove_3dn_running.sh > v2021rc3_tc112_${i}.out 2>&1
v_ok=`grep "sh : pass" v2021rc3_tc112_${i}.out |wc -l`
if [[ ${v_ok} = 0 ]];then
echo "fail"
break
fi

done
