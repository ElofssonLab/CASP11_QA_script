#!/bin/bash

# Filename:  filter_HETATM.sh
# Description: filter HETATM record from the model file
# Author: Nanjiang Shu (nanjiang.shu@scilifelab.se)

progname=`basename $0`
size_progname=${#progname}
wspace=`printf "%*s" $size_progname ""` 
usage="
Usage:  $progname [-l LISTFILE]  [-q]
        $wspace FILE 
Options:
  -l       FILE     Set the fileListFile, one filename per line
  -q                Quiet mode
  -h, --help        Print this help message and exit

Created 2014-07-02, updated 2014-07-02, Nanjiang Shu
"
PrintHelp(){ #{{{
    echo "$usage"
}
#}}}
FilterHETATM(){ #{{{
    local infile="$1"
    local tmpfile=$(mktemp /tmp/tmp.filter_HETATM.XXXXXXXXX) || { echo "Failed to create temp file" >&2; exit 1; }
    info=`grep HETATM $infile | head -n 1`
    if [ "$info" != "" ];then
        /bin/grep -v HETATM $infile > $tmpfile
        if [ -s $tmpfile ];then
            /bin/mv $tmpfile $infile
            echo "$infile filtered"
        fi
    fi
}
#}}}

if [ $# -lt 1 ]; then
    PrintHelp
    exit
fi

isQuiet=0
outpath=./
outfile=
fileListFile=
fileList=()

isNonOptionArg=0
while [ "$1" != "" ]; do
    if [ $isNonOptionArg -eq 1 ]; then 
        fileList+=("$1")
        isNonOptionArg=0
    elif [ "$1" == "--" ]; then
        isNonOptionArg=true
    elif [ "${1:0:1}" == "-" ]; then
        case $1 in
            -h | --help) PrintHelp; exit;;
            -outpath|--outpath) outpath=$2;shift;;
            -o|--o) outfile=$2;shift;;
            -l|--l|-list|--list) fileListFile=$2;shift;;
            -q|-quiet|--quiet) isQuiet=1;;
            -*) echo Error! Wrong argument: $1 >&2; exit;;
        esac
    else
        fileList+=("$1")
    fi
    shift
done

if [ "$fileListFile" != ""  ]; then 
    if [ -s "$fileListFile" ]; then 
        while read line
        do
            fileList+=("$line")
        done < $fileListFile
    else
        echo listfile \'$fileListFile\' does not exist or empty. >&2
    fi
fi

numFile=${#fileList[@]}
if [ $numFile -eq 0  ]; then
    echo Input not set! Exit. >&2
    exit 1
fi

for ((i=0;i<numFile;i++));do
    file=${fileList[$i]}
    FilterHETATM "$file"
done
