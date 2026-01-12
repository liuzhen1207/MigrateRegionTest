#!/bin/bash
parent_dir="$( cd "$( dirname "$0"  )" && pwd  )"
parent_dir="/data/iotdb"
db_commit=t_m_0525_c6ca964

iotdb_name="${db_commit}"

comm_param_file="common_param.txt"

function set_common_param()
{
   for val in `cat ./${comm_param_file}`
   do
      if [[ ${val} == *MAX_HEAP_SIZE* ]]
      then
              sed -i "s/^.*MAX_HEAP_SIZE=\"2G\"/${val}/g" ${parent_dir}/${iotdb_name}/conf/iotdb-common.properties
       #      echo "hello"
      else
              if [[ ${val} == *MAX_DIRECT_MEMORY_SIZE* ]]
              then
                 sed -i "s/^.*MAX_DIRECT_MEMORY_SIZE=.*/${val}/g" ${parent_dir}/${iotdb_name}/conf/iotdb-common.properties
              else
                 array=(${val//=/ })
                 param=${array[0]}
#             echo "$param"
                 sed -i "s/#[[:space:]]\+${param}=.*/${val}/g" ${parent_dir}/${iotdb_name}/conf/iotdb-common.properties
               fi
      fi
   done
}

cn_param_file="confignode_param.txt"

function set_cn_param()
{
   for val in `cat ./${cn_param_file}`
   do
      if [[ ${val} == *MAX_HEAP_SIZE* ]]
      then
              sed -i "s/^.*MAX_HEAP_SIZE=\"2G\"/${val}/g" ${parent_dir}/${iotdb_name}/conf/confignode-env.sh
       #      echo "hello"
      else
              if [[ ${val} == *MAX_DIRECT_MEMORY_SIZE* ]]
              then
                 sed -i "s/^.*MAX_DIRECT_MEMORY_SIZE=.*/${val}/g" ${parent_dir}/${iotdb_name}/conf/confignode-env.sh
              else
                 array=(${val//=/ })
                 param=${array[0]}
#             echo "$param"
                 sed -i "s/^.*${param}[ ]*=.*/${val}/g" ${parent_dir}/${iotdb_name}/conf/iotdb-confignode.properties
               fi
      fi
      if [[ ${val} == *HEAP_NEWSIZE* ]]
      then
              sed -i "s/#HEAP_NEWSIZE=\"2G\"/${val}/g" ${parent_dir}/${iotdb_name}/conf/confignode-env.sh
      fi
   done
}


dn_param_file="datanode_param.txt"
function set_dn_param()
{
   for val in `cat ./${dn_param_file}`
   do
      if [[ ${val} == *MAX_HEAP_SIZE* ]]
      then
              sed -i "s/^.*MAX_HEAP_SIZE=\"2G\"/${val}/g" ${parent_dir}/${iotdb_name}/conf/datanode-env.sh
       #      echo "hello"
      else
              if [[ ${val} == *MAX_DIRECT_MEMORY_SIZE* ]]
              then
                 sed -i "s/^.*MAX_DIRECT_MEMORY_SIZE=.*/${val}/g" ${parent_dir}/${iotdb_name}/conf/datanode-env.sh
              else
                 array=(${val//=/ })
                 param=${array[0]}
#             echo "$param"
                 sed -i "s/^.*${param}[ ]*=.*/${val}/g" ${parent_dir}/${iotdb_name}/conf/iotdb-datanode.properties
               fi
      fi
      if [[ ${val} == *HEAP_NEWSIZE* ]]
      then
              sed -i "s/#HEAP_NEWSIZE=\"2G\"/${val}/g" ${parent_dir}/${iotdb_name}/conf/datanode-env.sh
      fi
   done
}
set_common_param
set_cn_param
set_dn_param
