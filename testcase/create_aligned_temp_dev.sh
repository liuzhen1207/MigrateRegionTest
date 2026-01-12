db_commit=t_m_0525_c6ca964
db_dir="/data/iotdb/${db_commit}"

conn_ip=$1

${db_dir}/sbin/start-cli.sh -h ${conn_ip} -e "create database root.test.g_0;"
${db_dir}/sbin/start-cli.sh -h ${conn_ip} -e "create schema template t1 aligned(s_0 DOUBLE compressor=SNAPPY,\
s_1  DOUBLE ENCODING=RLE compressor=LZ4,\
s_2  DOUBLE ENCODING=TS_2DIFF compressor=GZIP,\
s_3 DOUBLE ENCODING=GORILLA compressor=ZSTD,\
s_4 DOUBLE compressor=ZSTD,\
s_5 DOUBLE ENCODING=CHIMP compressor=UNCOMPRESSED,\
s_6 DOUBLE compressor=LZ4,\
s_7 DOUBLE compressor=GZIP,\
s_8 DOUBLE compressor=ZSTD,\
s_9 DOUBLE compressor=ZSTD,\
s_10 DOUBLE compressor=SNAPPY,\
s_11 DOUBLE compressor=UNCOMPRESSED)        "

${db_dir}/sbin/start-cli.sh -h ${conn_ip} -e "set schema template t1 to root.test.g_0;"
