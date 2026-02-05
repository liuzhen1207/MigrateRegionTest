#!/bin/bash
sh -x tc53_mig_comping_user_root.sh > tc53_root.out 2>&1
sleep 10
sh -x tc53_mig_comping.sh > tc53.out 2>&1
