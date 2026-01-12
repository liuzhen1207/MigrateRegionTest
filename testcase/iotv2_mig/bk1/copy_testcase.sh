exec 3<./migrate_testcase_list.txt
while read line<&3
do
pre_name=`echo ${line}|awk -F '.' '{print $1}'`
cp -rp ../${line} ./${pre_name}_IoTV2.sh
echo ${pre_name}_IoTV2.sh >> IoTV2_migrate_testcase_list.txt 
done
