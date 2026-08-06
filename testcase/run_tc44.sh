for i in {1..20}
do
sh -x tc44_add_peer_stop_cn_remove-coord.sh > tc44_${i}.out 2>&1
sleep 5
done
