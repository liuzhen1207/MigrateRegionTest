for i in {1..9000}
do
/data1/iotdb/v1331_rc5_0703_d10e530/sbin/start-cli.sh -h 172.20.70.30 -e "select s1,s2,s3,s4,s5,s6 into root.db.d1(s1,s2,s3,s4,s5,s6) from root.db.d2;" &
/data1/iotdb/v1331_rc5_0703_d10e530/sbin/start-cli.sh -h 172.20.70.30 -e "select s1,s2,s3,s4,s5,s6 into root.db.d2(s1,s2,s3,s4,s5,s6) from root.db.d1;"
/data1/iotdb/v1331_rc5_0703_d10e530/sbin/start-cli.sh -h 172.20.70.30 -e "flush;"
done
