#!/bin/bash

cur_dir="$( cd "$( dirname "$0"  )" && pwd  )"
conf_file="${cur_dir}/../conf/test.conf"
nodeinfo_dir="${cur_dir}/../conf"

u_name=$(grep '^u_name=' "${conf_file}" | awk -F '=' '{print $2}')
db_dir=$(grep '^db_dir=' "${conf_file}" | awk -F '=' '{print $2}')

case_name=$1
backup_time=$2

if [[ -z "${case_name}" ]]; then
  echo "usage: $0 <case_name> [backup_time]"
  exit 1
fi

if [[ -n "${backup_time}" ]]; then
  backup_tag="${case_name}_${backup_time}"
else
  backup_tag="${case_name}"
fi

backup_root="${cur_dir}/../testcase/logs_backup"
backup_dir="${backup_root}/${backup_tag}"

backup_one_host_logs() {
  local role=$1
  local host_ip=$2
  local host_tag
  local target_file

  host_tag=$(echo "${host_ip}" | tr '.' '_')
  target_file="${backup_dir}/${role}_${host_tag}.tar.gz"

  ssh "${u_name}@${host_ip}" "cd ${db_dir} && if [[ -d logs ]]; then tar -czf - logs; else exit 2; fi" > "${target_file}"
}

mkdir -p "${backup_dir}"
cp -fp "${conf_file}" "${backup_dir}/test.conf"
cp -fp "${nodeinfo_dir}/confignode.txt" "${backup_dir}/confignode.txt"
cp -fp "${nodeinfo_dir}/datanode.txt" "${backup_dir}/datanode.txt"

printf 'case_name=%s\nbackup_time=%s\ndb_dir=%s\n' "${case_name}" "${backup_time}" "${db_dir}" > "${backup_dir}/meta.txt"

exec 3<"${nodeinfo_dir}/confignode.txt"
while read -r line <&3
do
  [[ -z "${line}" ]] && continue
  backup_one_host_logs "confignode" "${line}" || exit 1
done
exec 3<&-

exec 3<"${nodeinfo_dir}/datanode.txt"
while read -r line <&3
do
  [[ -z "${line}" ]] && continue
  backup_one_host_logs "datanode" "${line}" || exit 1
done
exec 3<&-

exit 0
