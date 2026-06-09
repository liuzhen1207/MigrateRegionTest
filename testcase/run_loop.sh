#!/bin/bash
for i in {1..10}
do
t=`date +%Y_%m_%d_%H_%M_%S`
sh -x tc30201_RMDN_no3_kill9dnsleep60s_remove_unknown_writable_view_obj.sh > ${t}_sleep.out 2>&1
wait 
done
for i in {1..10}
do
t=`date +%Y_%m_%d_%H_%M_%S`
sh -x tc302_RMDN_no3_kill9dn_remove_unknown_writable_view_obj.sh> ${t}_nosleep.out 2>&1      
wait
done


