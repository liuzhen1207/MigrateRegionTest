for i in {1..3}
do
sh -x tc45_add_peer_stop_mig-region_2dn.sh > v1342_tc45_${i}.out 2>&1
v_ok=`grep "sh : pass" v1342_tc45_${i}.out |wc -l`
if [[ ${v_ok} = 0 ]];then
echo "fail"
break
fi

done
