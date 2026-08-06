#!/bin/bash
for i in {1..7200}
do
/data1/iotdb/testdb/v20101_rc3_0612_d9140d3/sbin/start-cli.sh -u root -h 172.20.70.4 -sql_dialect tree -timeout 3600 -e 'show migrations;' >> v20101_rc3_show_mig.out
/data1/iotdb/testdb/v20101_rc3_0612_d9140d3/sbin/start-cli.sh -u root -h 172.20.70.4 -sql_dialect table -timeout 3600 -e 'show migrations;' >> v20101_rc3_show_mig.out
sleep 2
done
