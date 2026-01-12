exec 3<./IoTV2_migrate_testcase_list.txt
while read line<&3
do
pre_name=`echo ${line}|awk -F '.' '{print $1}'`
cp -rp ./${line} ./${pre_name}_IoTV1_has_table.sh
echo ${pre_name}_IoTV1_has_table.sh >> IoTV1_has_table_migrate_testcase_list.txt 
done
