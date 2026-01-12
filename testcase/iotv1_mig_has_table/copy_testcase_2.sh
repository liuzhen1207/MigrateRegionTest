exec 3<./IoTV1_has_table_migrate_testcase_list.txt
while read line<&3
do
pre_name=`echo ${line}|awk -F "_IoTV2" '{print $1$2}'`
echo "${pre_name}"
cp -rp ./${line} ./${pre_name}
echo ${pre_name} >> IoTV1_has_table_migrate_testcase_list_2.txt 
done
