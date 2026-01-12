cur_dir="$( cd "$( dirname "$0"  )" && pwd  )"
conf_file="${cur_dir}/../conf/test.conf"
nodeinfo_dir="${cur_dir}/../conf"
u_name=cluster
exec 3<${nodeinfo_dir}/datanode.txt
while read node <&3
do
   v_pid_str=`ssh ${u_name}@${node} "sudo jps|grep -i datanode"`
   v_pid=`echo ${v_pid_str}|awk '{print $1}'`
   echo "${v_pid}"
   v_ip=`echo ${node}|awk -F '.' '{print $4}'`
   ssh ${u_name}@${node} "sudo jstack -l ${v_pid}" > dn_${v_ip}_stack.out 
done

