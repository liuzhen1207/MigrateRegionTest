#!/bin/bash
for i in {1..55}
do
file1=`sed -n "${i}p" ./IoTV1_has_table_migrate_testcase_list.txt`
file2=`sed -n "${i}p" ./IoTV2_migrate_testcase_list.txt`
diff_res=`diff ${file1} ${file2}`
echo "diff ${file1} ${file2}  --------------------------------------"
echo "${diff_res}"
done
