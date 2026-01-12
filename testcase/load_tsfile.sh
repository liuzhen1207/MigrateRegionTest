db_commit=t_m_0525_c6ca964
conn_ip=$1
desc=$2
install_dir="/data/iotdb"
db_dir="${install_dir}/${db_commit}"
dir="$( cd "$( dirname "$0"  )" && pwd  )"
begin_index=21
sleep 120

for i in {1..20} 
do
v_file_num=`find ${db_dir}/data/ -name "*-${begin_index}-0-0.tsfile.resource"|wc -l`
if [[ ${v_file_num} -gt 0 ]];then
tmp_file=tmp_${desc}_tsfile_${begin_index}
mkdir ${tmp_file}
find ${db_dir}/data/ -name *-${begin_index}-0-0.tsfile.resource >${tmp_file}/tmp.txt
exec 3<./${tmp_file}/tmp.txt
while read tsfile true<&3
do
v_tsfile=`echo $tsfile|awk -F "tsfile" '{print $1"tsfile"}'`
cp -rp ${v_tsfile} ./${tmp_file}
cp -rp ${tsfile} ./${tmp_file}
sleep 60
${db_dir}/sbin/start-cli.sh -h ${conn_ip} -e "load \"${dir}/${tmp_file}\" verify=false sglevel=2 onSuccess=none"
done
begin_index=$((begin_index+40))
fi
sleep 60
done
