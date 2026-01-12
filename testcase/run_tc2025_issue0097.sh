desc=$1
for i in {1..15}
do
sh -x tc2025_issue0097.sh > ${desc}_iotv2_${i}.out 2>&1
v_ok=`grep "sh : pass" ${desc}_iotv2_${i}.out |wc -l`
if [[ ${v_ok} = 0 ]];then
echo "fail"
break
fi

done
