exec 3<./tc_list.txt
while read line<&3
do
sed -i 's/dr_rep_num=2/dr_rep_num=3/g' /auto_test/auto_test_shell/testcase/${line} 
done
