#!/bin/bash

rundir=`dirname $0`
cd $rundir

basedir=$PWD

url=http://www.predictioncenter.org/download_area/CASP11/server_predictions/
indexfile_html=server_prediction.index.html
wget  $url -O  $indexfile_html
indexfile_text=server_prediction.index.txt
html2text $indexfile_html > $indexfile_text


tgz_filelist=`cat $indexfile_text | grep "[[CMP]]" | awk '{print $2}'`
echo "$tgz_filelist"

if [ ! -d stage1 ];then
    mkdir -p stage1
fi
if [ ! -d stage2 ];then
    mkdir -p stage2
fi
if [ ! -d all ];then
    mkdir -p all
fi


for file in $tgz_filelist; do
    outdir=
    case $file in 
        *.stage1.*) outdir=stage1;;
        *.stage2.*) outdir=stage2;;
        *) outdir=all;;
    esac
    cd $outdir
    if [ ! -s $file ];then
        wget $url/$file -O $file
        tar -xvzf $file
    fi
    cd $basedir
done
