#!/bin/bash

rundir=`dirname $0`
$rundir/download_prediction.sh
$rundir/run_QA_proq2.pl
$rundir/archive_QA.sh
