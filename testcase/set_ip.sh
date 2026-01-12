#!/bin/bash
parent_dir="$( cd "$( dirname "$0"  )" && pwd  )"
parent_dir="/data/iotdb"
db_commit=t_m_0525_c6ca964
iotdb_name="${db_commit}"
first_confignode_ip=`head -1 ./confignode.txt`
cn_internal_port=10710
datanode_confignode_ip=""
u_name="cluster"
exec 4<confignode.txt
while read c_node <&4
do
if [[ $datanode_confignode_ip = "" ]];then
   datanode_confignode_ip="${c_node}:${cn_internal_port}"
else
   datanode_confignode_ip=${datanode_confignode_ip}",${c_node}:${cn_internal_port}"
fi
done

function set_confignode_ip()
{
   internal_ip=$1
   confignode_rpc_address=${internal_ip}

   ssh ${u_name}@${internal_ip} "sed -i 's/^cn_target_config_node_list=.*/cn_target_config_node_list='${first_confignode_ip}:${cn_internal_port}'/g' ${parent_dir}/${iotdb_name}/conf/iotdb-confignode.properties"
   ssh ${u_name}@${internal_ip} "sed -i 's/^cn_internal_address=.*/cn_internal_address='${confignode_rpc_address}'/g' ${parent_dir}/${iotdb_name}/conf/iotdb-confignode.properties"
}
function set_datanode_ip()
{
   internal_ip=$1
   datanode_rpc_address=${internal_ip}
   ssh ${u_name}@${internal_ip} "sed -i 's/^dn_internal_address=.*/dn_internal_address='${internal_ip}'/g' ${parent_dir}/${iotdb_name}/conf/iotdb-datanode.properties"
   ssh ${u_name}@${internal_ip} "sed -i 's/^dn_rpc_address=.*/dn_rpc_address='${datanode_rpc_address}'/g' ${parent_dir}/${iotdb_name}/conf/iotdb-datanode.properties"
   ssh ${u_name}@${internal_ip} "sed -i 's/^dn_target_config_node_list=.*/dn_target_config_node_list='${datanode_confignode_ip}'/g' ${parent_dir}/${iotdb_name}/conf/iotdb-datanode.properties"

}
exec 3<datanode.txt
while read d_node <&3
do
set_datanode_ip ${d_node}
done

exec 4<confignode.txt
while read c_node <&4
do
set_confignode_ip ${c_node}
done
