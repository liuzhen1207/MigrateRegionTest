parent_dir="/data/iotdb"
db_commit=v1301_rc1_1101_768169c
iotdb_name="${db_commit}"

diff ${parent_dir}/${iotdb_name}/conf/confignode-env.sh ${parent_dir}/${iotdb_name}/conf_orig/confignode-env.sh
diff ${parent_dir}/${iotdb_name}/conf/datanode-env.sh ${parent_dir}/${iotdb_name}/conf_orig/datanode-env.sh
diff ${parent_dir}/${iotdb_name}/conf/iotdb-common.properties ${parent_dir}/${iotdb_name}/conf_orig/iotdb-common.properties
diff ${parent_dir}/${iotdb_name}/conf/iotdb-confignode.properties ${parent_dir}/${iotdb_name}/conf_orig/iotdb-confignode.properties
diff ${parent_dir}/${iotdb_name}/conf/iotdb-datanode.properties ${parent_dir}/${iotdb_name}/conf_orig/iotdb-datanode.properties
