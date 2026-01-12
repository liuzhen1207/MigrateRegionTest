#!/bin/bash
sudo ifconfig eth0 down
sleep 60
sudo ifconfig eth0 up
