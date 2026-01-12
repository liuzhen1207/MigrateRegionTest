#!/bin/bash
db_commit=t_m_0525_c6ca964
db_dir="/data/iotdb/${db_commit}"
conn_ip=$1
${db_dir}/sbin/start-cli.sh -h ${conn_ip} -h ${conn_ip} -e "create database root.test.g_0;"
client_num=20
function create_1_dev()
{
   desc=$1
	${db_dir}/sbin/start-cli.sh -h ${conn_ip} -e "create timeseries root.test.g_0.d_${desc}.s_0 with  datatype=DOUBLE,compressor=SNAPPY tags(s0_tag1=s0_tag1, s0_tag2=s0_tag2) attributes(s0_attr1=s0_attr1, s0_attr2=s0_attr2);"
	${db_dir}/sbin/start-cli.sh -h ${conn_ip} -e "create timeseries root.test.g_0.d_${desc}.s_1 with datatype=DOUBLE ,ENCODING=RLE ,compressor=LZ4 tags(s1_tag1=s1_tag1, s1_tag2=s1_tag2) attributes(s1_attr1=s1_attr1, s1_attr2=s1_attr2);"
	${db_dir}/sbin/start-cli.sh -h ${conn_ip} -e "create timeseries root.test.g_0.d_${desc}.s_2 with datatype=DOUBLE ,ENCODING=TS_2DIFF ,compressor=GZIP tags(s2_tag1=s2_tag1, s2_tag2=s2_tag2) attributes(s2_attr1=s2_attr1, s2_attr2=s2_attr2);"
	${db_dir}/sbin/start-cli.sh -h ${conn_ip} -e "create timeseries root.test.g_0.d_${desc}.s_3 with datatype=DOUBLE ,ENCODING=GORILLA ,compressor=ZSTD tags(s3_tag1=s3_tag1, s3_tag2=s3_tag2) attributes(s3_attr1=s3_attr1, s3_attr2=s3_attr2);"
	${db_dir}/sbin/start-cli.sh -h ${conn_ip} -e "create timeseries root.test.g_0.d_${desc}.s_4 with datatype=DOUBLE compressor=ZSTD tags(s4_tag1=s4_tag1, s4_tag2=s4_tag2) attributes(s4_attr1=s4_attr1, s4_attr2=s4_attr2);"
	${db_dir}/sbin/start-cli.sh -h ${conn_ip} -e "create timeseries root.test.g_0.d_${desc}.s_5 with datatype=DOUBLE ,ENCODING=CHIMP ,compressor=UNCOMPRESSED tags(s5_tag1=s5_tag1, s5_tag2=s5_tag2) attributes(s5_attr1=s5_attr1, s5_attr2=s5_attr2);"
	${db_dir}/sbin/start-cli.sh -h ${conn_ip} -e "create timeseries root.test.g_0.d_${desc}.s_6 with datatype=DOUBLE ,compressor=LZ4 tags(s6_tag1=s6_tag1, s6_tag2=s6_tag2) attributes(s6_attr1=s6_attr1, s6_attr2=s6_attr2);"
	${db_dir}/sbin/start-cli.sh -h ${conn_ip} -e "create timeseries root.test.g_0.d_${desc}.s_7 with datatype=DOUBLE ,compressor=GZIP tags(s7_tag1=s7_tag1, s7_tag2=s7_tag2) attributes(s7_attr1=s7_attr1, s7_attr2=s7_attr2);"
	${db_dir}/sbin/start-cli.sh -h ${conn_ip} -e "create timeseries root.test.g_0.d_${desc}.s_8 with datatype=DOUBLE ,compressor=ZSTD tags(s8_tag1=s8_tag1, s8_tag2=s8_tag2) attributes(s8_attr1=s8_attr1, s8_attr2=s8_attr2);"
	${db_dir}/sbin/start-cli.sh -h ${conn_ip} -e "create timeseries root.test.g_0.d_${desc}.s_9 with datatype=DOUBLE ,compressor=ZSTD tags(s9_tag1=s9_tag1, s9_tag2=s9_tag2) attributes(s9_attr1=s9_attr1, s9_attr2=s9_attr2);"
	${db_dir}/sbin/start-cli.sh -h ${conn_ip} -e "create timeseries root.test.g_0.d_${desc}.s_10 with datatype=DOUBLE ,compressor=SNAPPY tags(s10_tag1=s10_tag1, s10_tag2=s10_tag2) attributes(s10_attr1=s10_attr1, s10_attr2=s10_attr2);"
	${db_dir}/sbin/start-cli.sh -h ${conn_ip} -e "create timeseries root.test.g_0.d_${desc}.s_11 with datatype=DOUBLE ,compressor=UNCOMPRESSED tags(s11_tag1=s11_tag1, s11_tag2=s11_tag2) attributes(s11_attr1=s11_attr1, s11_attr2=s11_attr2);"
${db_dir}/sbin/start-cli.sh -h ${conn_ip} -e "ALTER timeseries root.test.g_0.d_${desc}.s_0 UPSERT ALIAS=s0Alias;  " 
${db_dir}/sbin/start-cli.sh -h ${conn_ip} -e "ALTER timeseries root.test.g_0.d_${desc}.s_1 UPSERT ALIAS=s1Alias;"    
${db_dir}/sbin/start-cli.sh -h ${conn_ip} -e "ALTER timeseries root.test.g_0.d_${desc}.s_2 UPSERT ALIAS=s2Alias;"
${db_dir}/sbin/start-cli.sh -h ${conn_ip} -e "ALTER timeseries root.test.g_0.d_${desc}.s_3 UPSERT ALIAS=s3Alias;"
${db_dir}/sbin/start-cli.sh -h ${conn_ip} -e "ALTER timeseries root.test.g_0.d_${desc}.s_4 UPSERT ALIAS=s4Alias;"
${db_dir}/sbin/start-cli.sh -h ${conn_ip} -e "ALTER timeseries root.test.g_0.d_${desc}.s_5 UPSERT ALIAS=s5Alias;"
${db_dir}/sbin/start-cli.sh -h ${conn_ip} -e "ALTER timeseries root.test.g_0.d_${desc}.s_6 UPSERT ALIAS=s6Alias;"
${db_dir}/sbin/start-cli.sh -h ${conn_ip} -e "ALTER timeseries root.test.g_0.d_${desc}.s_7 UPSERT ALIAS=s7Alias;"
${db_dir}/sbin/start-cli.sh -h ${conn_ip} -e "ALTER timeseries root.test.g_0.d_${desc}.s_8 UPSERT ALIAS=s8Alias;"
${db_dir}/sbin/start-cli.sh -h ${conn_ip} -e "ALTER timeseries root.test.g_0.d_${desc}.s_9 UPSERT ALIAS=s9Alias;"
${db_dir}/sbin/start-cli.sh -h ${conn_ip} -e "ALTER timeseries root.test.g_0.d_${desc}.s_10 UPSERT ALIAS=s10Alias;"
${db_dir}/sbin/start-cli.sh -h ${conn_ip} -e "ALTER timeseries root.test.g_0.d_${desc}.s_11 UPSERT ALIAS=s11Alias;"
}
for i in {0..999}
do
   create_1_dev $i &
   if [ $((i%client_num)) = "0" ];then
      wait
   fi
done
wait
