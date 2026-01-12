sync
sudo -s <<EOF
echo 3 >/proc/sys/vm/drop_caches
EOF
