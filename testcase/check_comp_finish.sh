#!/bin/bash
db_commit=t_m_0525_c6ca964
install_dir="/data/iotdb"
db_dir="${install_dir}/${db_commit}"
dir="$( cd "$( dirname "$0"  )" && pwd  )"
conn_ip="172.20.70.28"
bm_dir="/data/iotdb/benchmark/bm_20230428_e7dad04"
test_desc_list=("normal" "aligned" "normal_temp" "aligned_temp")
u_name="cluster"
function comp_is_finish()
{
        i=0
	while true
	do
		comp_log_num=`find ${db_dir}/data/datanode/data/ -name *compaction.log|wc -l`
		if [[ ${comp_log_num} = "0" ]];then
			let i++
			sleep 60
		else
			sleep 300
		fi
		if [[ $i = "4" ]];then
			echo "compaction is finished."
			break
		fi
        done
}
function stop_db()
{
    desc=$1
	sudo ${db_dir}/sbin/stop-standalone.sh
	sleep 60
	while true
	do
	   stop_ok=`sudo jps|grep -i node|wc -l`
	   if [[ ${stop_ok} = "0" ]];then
		   echo "stop cluster successfully."
		   break
	   else
		   sleep 5
	   fi
        done
        bk_date=`date "+%Y-%m-%d"`
        mv ${db_dir}/data ${db_dir}/data_$desc
        mv ${db_dir}/logs ${db_dir}/logs_$desc

}
function start_db()
{
desc=$1
sudo -s <<EOF
echo 3 >/proc/sys/vm/drop_caches
EOF
if ssh ${u_name}@${conn_ip} test -d ${install_dir}/${db_commit}/data; then
echo "license is exist."
else
   ssh ${u_name}@${conn_ip} "cp -rp ${install_dir}/timecho_license ${install_dir}/${db_commit}/data"
fi

        nohup sudo ${db_dir}/sbin/start-standalone.sh > /dev/null 2>&1 &
        sleep 60
        while true
        do
           start_ok=`${db_dir}/sbin/start-cli.sh -h ${conn_ip} -e "show version"|grep -i "Total line number"|wc -l`
           if [[ ${start_ok} = "1" ]];then
                   echo "start cluster successfully."
                   break
	   else
		   sleep 5
           fi
        done
if [ -n "$desc" ];then
   sh "./create_${desc}_dev.sh" ${conn_ip}
fi
}
function start_bm()
{
	desc=$1
	cd ${bm_dir}
	./run.sh ${desc} &
        sleep 10
        cd ${dir}
        ./load_tsfile.sh ${conn_ip} ${desc}
        wait
        cd ${dir}
        ${db_dir}/sbin/start-cli.sh -h ${conn_ip} -e "flush"
}
function check_data()
{
    res_desc=$1
    tmp_res_system=`${db_dir}/sbin/start-cli.sh -h ${conn_ip} -timeout 36000 -e "select sum(value) from root.__system.** align by device;"`
    echo "$tmp_res_system" >./tmp_${res_desc}.out
    res_system=`cat ./tmp_${res_desc}.out|grep root|awk -F "|" '{sum+=$3}END{print sum}' `
    ${db_dir}/sbin/start-cli.sh -h ${conn_ip} -timeout 36000 -e "select count(s_0) from root.test.g_0.** align by device;" > ${res_desc}_q_res.out
    res_iotdb_db=`cat ${res_desc}_q_res.out |grep root|awk -F '|' '{sum+=$3}END{print sum}'`
    sum_res_iotdb_db=$((res_iotdb_db*12))
    if [ ${sum_res_iotdb_db} = ${res_system} ];then
       echo "${db_commit} $res_desc system: ${res_system} user: ${sum_res_iotdb_db} pass." >> test.log
    else
       bm_res=`cat ${bm_dir}/${res_desc}_res.out`
       echo "${db_commit} $res_desc system: ${res_system} user: ${sum_res_iotdb_db} benchmark res: ${bm_res} fail." >> test.log
    fi
       through_res=`cat ${bm_dir}/${res_desc}_through_res.out` 
       echo "${db_commit} $res_desc throughput(point/s):${through_res}" >> throughput_res.log
}
function get_compaction_cost()
{  desc=$1
   sudo gunzip ${db_dir}/logs/log-datanode-compaction*gz
   v_unseq=`grep "Unsequence InnerSpaceCompaction task finishes successfully"  ${db_dir}/logs/*compaction*|wc -l`
   v_seq=`grep "Sequence InnerSpaceCompaction task finishes successfully"  ${db_dir}/logs/*compaction*|wc -l`
   v_cross=`grep " CrossSpaceCompaction task finishes successfully"  ${db_dir}/logs/*compaction*|wc -l`

   sum_cost=`grep "SpaceCompaction task finishes successfully" ${db_dir}/logs/*compaction*|awk -F "time cost is " '{print $2}'|awk '{sum+=$1}END{print sum}'`
   echo "${db_commit} ${desc} compaction sum cost: ${sum_cost} ,Sequence InnerSpaceCompaction: ${v_seq} ,Unsequence InnerSpaceCompaction: ${v_unseq},CrossSpaceCompaction:${v_cross}" >> compaction_cost_res.out
}
for(( idx=0;idx<${#test_desc_list[@]};idx++))
do
test_desc=${test_desc_list[idx]} 
start_db ${test_desc}
start_bm ${test_desc}
comp_is_finish
check_data ${test_desc}
get_compaction_cost ${test_desc}
stop_db ${test_desc}
done
