#!/bin/bash
a=1
b=10

for ((i=$a;i<=$b;i+=2))
do
echo $i
done
i=$((a+b+1))
echo $i
