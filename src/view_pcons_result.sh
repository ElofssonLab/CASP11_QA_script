#!/bin/bash

rundir=`dirname $0` 
cd $rundir/../
red='\e[0;31m'
NC='\e[0m' # No Color

for file in $(find stage2 -name "pcomb.dat" | sort -g); do dirname=`dirname $file`; targetid=`basename $dirname`; echo -e "\n${red}$targetid${NC}"; sort -k2,2rg $file | awk '{print NR "\t" $1 "\t" $2}' | grep -i "pcons\|^1\>"  ; done
