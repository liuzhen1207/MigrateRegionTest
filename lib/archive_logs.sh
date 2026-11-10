#!/bin/bash
# ============================================================================
# lib/archive_logs.sh —— 通用「证据归档」
#
# 用法：在用例脚本头部加两行
#     source "${cur_dir}/../lib/archive_logs.sh"
#     trap 'archive_logs' EXIT
# 即可。脚本退出时自动把 CN/DN 的 logs 与常见中间产物归档。
#
# 背景：本 skill 是串行跑批，**下一个用例**的 clean_env 会清掉本轮的 data/logs，
#       等发现问题时现场已经没了（2026-11-10 查 RC1 的 NPE 就吃过这个亏）。
#
# 特点：
#   · 幂等：内部有 _LOG_ARCHIVED 守卫，重复调用只归档一次
#   · 自足：优先用用例已定义的变量，缺失时回落到 conf/test.conf，不依赖调用方
#   · 兜底：归档失败一律只 warn 不中断，绝不影响用例判定
#   · 保留：每个用例只留最近 KEEP 次，避免长期跑批堆满磁盘
# ============================================================================
archive_logs()
{
   [ "${_LOG_ARCHIVED:-0}" = "1" ] && return 0
   _LOG_ARCHIVED=1

   local _cfg="${conf_file:-${cur_dir}/../conf/test.conf}"
   local _u="${u_name:-$(grep '^u_name=' "$_cfg" 2>/dev/null | cut -d= -f2)}"
   local _db="${db_dir:-$(grep '^db_dir=' "$_cfg" 2>/dev/null | cut -d= -f2)}"
   local _ver="${v_cur_db:-$(grep '^v_cur_db=' "$_cfg" 2>/dev/null | cut -d= -f2)}"
   local _ni="${nodeinfo_dir:-$(dirname "$_cfg")}"
   local _name="${SCRIPT_NAME:-$(basename "$0")}"
   local KEEP="${ARCHIVE_KEEP:-10}"

   [ -z "${_db}" ] && { echo "  [archive] db_dir 未知，跳过"; return 0; }
   [ -z "${_ver}" ] && _ver="unknown"

   local _arch_dir="${cur_dir}/../log_archive/${_ver}/${_name%.sh}_$(date +%Y%m%d_%H%M%S)"
   mkdir -p "${_arch_dir}" 2>/dev/null || { echo "  [archive] 创建目录失败，跳过"; return 0; }

   # 节点集合：CN + DN（去重）
   local _hosts
   _hosts=$( { cat "${_ni}/confignode.txt" 2>/dev/null; cat "${_ni}/datanode.txt" 2>/dev/null; } | sort -u | tr "\n" " " )
   [ -z "${_hosts}" ] && _hosts="${v_cn_ips:-}"

   local _h _n=0
   for _h in ${_hosts}; do
      [ -z "${_h}" ] && continue
      ssh -o BatchMode=yes -o ConnectTimeout=8 "${_u}@${_h}" \
          "sudo tar czf - ${_db}/logs 2>/dev/null" 2>/dev/null > "${_arch_dir}/${_h}.logs.tgz"
      if [ -s "${_arch_dir}/${_h}.logs.tgz" ]; then _n=$((_n+1)); else rm -f "${_arch_dir}/${_h}.logs.tgz"; fi
   done

   # 中间产物（下个用例会覆盖，一并存下）
   local _f
   for _f in mig.out mig_id_info.txt q_exp.out q_act.out q_exp2.out q_act2.out \
             tc7_bef_mig_cluster.out all_dn_id.txt \
             region_pair.out show_regions.out show_datanodes.out show_cluster.out; do
      [ -f "${cur_dir}/${_f}" ] && cp -p "${cur_dir}/${_f}" "${_arch_dir}/" 2>/dev/null
   done

   # 保留策略
   ls -dt "${cur_dir}/../log_archive/${_ver}/${_name%.sh}_"* 2>/dev/null | tail -n +$((KEEP+1)) | while read -r _old; do
      rm -rf "${_old}" 2>/dev/null
   done

   echo "  [archive] 已归档 ${_n} 个节点日志 -> ${_arch_dir}（共 $(ls -1 "${_arch_dir}" 2>/dev/null | wc -l) 个文件）"
}
