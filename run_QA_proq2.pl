#!/usr/bin/perl -w
use Cwd 'abs_path';
use File::Basename;
use File::Spec;
use File::Temp;
my $rundir = dirname(abs_path($0));


#ChangeLog 2014-07-02 
#   filter HETATM record from the model files, otherwise proq2 score.linuxxxx
#   may fail
my $exec_proq2 = "/var/www/pcons/cgi-bin/run_proq2.pl";
my $exec_pcons = "/var/www/pcons/bin/pcons.linux";
my $CASP11_TS_DIR = "/var/www/pcons/CASP11_TS";
my $CASP11_QA_DIR = $rundir;

# my @to_email_list = (
#     "models\@predictioncenter.org",
#     "nanjiang.shu\@gmail.com");

my @to_email_list = (
    "nanjiang.shu\@gmail.com");

my @stagelist = ("all", "stage1","stage2");
my $date = localtime();

print "\nStart $0 at $date\n\n";

chdir($rundir);
my $stage = "";

foreach $stage(@stagelist){

    my $casp_model_nr = "";
    my $stage_str = ""; # string to get tarball, e.g. T0762.stage1.3D.srv.tar.gz T0762.3D.srv.tar.gz
    if ($stage eq "stage1"){
        $casp_model_nr = 1;
        $stage_str = ".$stage";
    }elsif($stage eq "stage2"){
        $casp_model_nr = 2;
        $stage_str = ".$stage";
    }elsif($stage eq "all"){
        $casp_model_nr = 3;
        $stage_str = "";
    }else{
        next;
    }
    print "\n$stage\n\n";
    chdir($stage);

    my $WORKDIR="$rundir/$stage";

    $date = localtime();
    my @job_folders=();
    opendir(DIR,"$rundir/$stage");
    my @folders=readdir(DIR);
    closedir(DIR);
    foreach my $folder(@folders) {
        if($folder=~/^T\d+$/ || $folder=~/^T\d+-D1$/ && (-d "$folder" || -l "$folder")) {
            push(@job_folders,$folder);
        }
    }
    foreach my $folder(sort @job_folders) {
        print "Folder: $folder\n";
        my $tarball = "$WORKDIR/$folder$stage_str.3D.srv.tar.gz";
        print "Tarball: $tarball\n";
        #next;

        if (-f $tarball && -M $tarball > 2.0){
            print "$tarball older than 2 days, Ignore.\n";
            next;
        }
        my $targetseq = "$CASP11_TS_DIR/$folder/sequence";
        if ($folder =~ /-D1$/){
            my $origfolder = $folder;
            $origfolder =~ s/-D1$//g;
            $targetseq = "$CASP11_TS_DIR/$origfolder/sequence";
        }
        if (! -s $targetseq){
            print "targetseq $targetseq does not exist. Ingore\n";
            exit;
        }

        my $seq = `cat $targetseq`;
        chomp($seq);
        my $seqlength = length($seq);

        my $outdir = "$WORKDIR/proq2/$folder";
        if (! -d $outdir){
            `mkdir -p $outdir`;
        }
        my $modellistfile = "$WORKDIR/proq2/$folder/pcons.input";
        `find $WORKDIR/$folder/ -type f -name "*TS[0-9]" > $modellistfile`;
        `find $WORKDIR/$folder/ -type f -name "*TS[0-9]*-D1" >> $modellistfile`;
        `$rundir/filter_HETATM.sh -l $modellistfile`; #added 2014-07-02

        if ($stage eq "stage1"){
            # for stage1, add also the pcons.net emsembles to it to get better
            # pcons score statistics
            `find $CASP11_TS_DIR/$folder/models/modeller/ -type f -name "*.pdb" >> $modellistfile`;
        }

        if (-s $modellistfile){
            #my $cmd = "$exec_proq2 -targetseq $targetseq -modellist $modellistfile -outpath $outdir -forcewrite";
            my $cmd = "$exec_proq2 -targetseq $targetseq -modellist $modellistfile -outpath $outdir ";
            $date = localtime();
            print "[$date]: $cmd\n";
            `$cmd`;
            $date = localtime();
            `echo $date > $outdir/FINISHED`;
        }

        # run pcons
        my $pcons_outfile = "$WORKDIR/proq2/$folder/pcons.output";
        if (! -s $pcons_outfile){
            print "$exec_pcons -i $modellistfile -L $seqlength -casp -A\n";
            `$exec_pcons -i $modellistfile -L $seqlength -casp -A > $pcons_outfile`;
        }

        if (! -s $pcons_outfile){
            print "$pcons_outfile does not exist. pcons failed \n";
            next;
        }
        my ($pcons_score,$local_quality)=read_QA($pcons_outfile);
        my %pcons_score=%{$pcons_score};
        my %local_quality=%{$local_quality};

        print "Generating CASP11 outputs for models ...\n";
        my $casp_reg_code = "6685-2065-9124";
        my $casp_target_id = $folder;

        my @modelnamelist = keys(%pcons_score);
        my $out_datfile = "$WORKDIR/proq2/$folder/pcomb.dat";
        open (DAT, ">$out_datfile");

        foreach my $modelname (@modelnamelist){
            if($modelname =~ /pcons.*pdb/){
                # ignore pcons.net emsembles, the should not be included in the
                # QA models
                next;
            }


            my $proq2file = "$WORKDIR/proq2/$folder/$modelname.proq2";
            my $proq2resfile = "$WORKDIR/proq2/$folder/$modelname.proq2res";
            if(-e $proq2file && -e $proq2resfile && defined($pcons_score{$modelname}) && defined($local_quality{$modelname})) {
                my $proq2_str = `cat $proq2file`;
                chomp($proq2_str);
                my @temp = split(/\s+/, $proq2_str);
                my $proq2_s = "";
                if (scalar(@temp) > 2){
                    $proq2_s = $temp[1];
                }else{
                    next;
                }
                # read in proq2 local prediction
                #==================
                my $proq2res_str = `cat $proq2resfile | awk '{printf("%s ", \$2)}'`;
                chomp($proq2res_str);
                my @proq2res_score = split(/\s+/, $proq2res_str);
                my $num_res_proq2 = scalar(@proq2res_score);

                my $proq2res_index_str = `cat $proq2resfile | awk '{printf("%d ", \$1-1)}'`;
                chomp($proq2res_index_str);
                my @proq2res_index = split(/\s+/, $proq2res_index_str);

                my %proq2res_dict = ();

                for (my $i = 0 ; $i < $num_res_proq2; $i++){
#                     print "$proq2res_index[$i]"."\n";
                    $proq2res_dict{$proq2res_index[$i]} = $proq2res_score[$i];
                }
                #==================

                if ($proq2_s eq "nan" || $proq2_s < 0 || $proq2_s > 1){
                    #if got wired proq2 score, recalculate it from the local
                    #proq2 score
                    my $sum = 0;
                    foreach my $score(@proq2res_score){
                        if($score>=0 && $score <=1){
                            $sum += $score;
                        }
                    }
                    $proq2_s = $sum/$seqlength;
                    `awk -v score=$proq2_s '{print \$1, score, \$3, \$4}' $proq2file > $proq2file.recalculated`; 
                }



#                 my $pcons_local_score_str = $local_quality{$modelname};
#                 chomp($pcons_local_score_str);
#                 my @pcons_local_score = split((/\s+/, $pcons_local_score_str));
                my @pcons_local_score =  @{$local_quality{$modelname}};

                my $num_res_pcons = scalar(@pcons_local_score);

                my $pcons_s = $pcons_score{$modelname};
                my $pcomb_s = $pcons_s * 0.8 + $proq2_s * 0.2;

#                 print join(" ", @proq2res_score) ."\n";

                if ($num_res_proq2 != $num_res_pcons){
                    print "num_res_pcons ($num_res_pcons) != num_res_proq2 ($num_res_proq2)\n";
#                     next;
                }

                my @newlist = ();
                for (my $i = 0 ; $i < $num_res_pcons; $i++){
                    my $s_pcons = $pcons_local_score[$i];

                    my $s_proq2 ;
                    if (defined($proq2res_dict{$i})){
                        $s_proq2 = $proq2res_dict{$i};
#                         print "DEFINED\n";
                    }else{
                        $s_proq2 = -1;
#                         print "NOT DEFINED\n";
                    }

                    my $s_pcomb ;

                    if($s_pcons eq "X" || ($s_proq2 < 0 || $s_proq2 >1))
                    #if($s_pcons eq "X" )
                    {
                        print "$folder, $stage, $modelname, s_pcons[$i]=$s_pcons, s_proq2[$i] = $s_proq2\n";
                        $s_pcomb = "X";
                    }
                    else
                    {
                        $s_pcomb = S2d(0.8*d2S($s_pcons)+0.2*$s_proq2);
                        #if ($s_pcomb eq "nan" || $s_pcomb < 0 || $s_pcomb > 1)
                        if ($s_pcomb eq "nan" || $s_pcomb < 0)
                        {
                            $s_pcomb = 'X';
                        }else{
                            $s_pcomb = sprintf("%.3f",$s_pcomb);
                        }
                    }
                    push(@newlist, $s_pcomb);
                }
                print DAT "$modelname $pcomb_s ". join(" ", @newlist) . "\n";
            }
        }
        close(DAT);

        my $out_mailfile = "$WORKDIR/proq2/$folder/pcomb.mail";
        open (MAIL, ">$out_mailfile");
        print MAIL "PFRMAT QA\n";
        print MAIL "TARGET $casp_target_id\n";
        print MAIL "AUTHOR $casp_reg_code\n";
        print MAIL "METHOD Pcomb\n";
        print MAIL "MODEL $casp_model_nr\n";
        print MAIL "QMODE 2\n";
        close(MAIL);
        # fixed the bug 2014-05-12, try to filter emsembles from pcons.net to
        # the QA output file
        `sort -k2,2rg $out_datfile | grep -v "pcons.*pdb" | awk '{for(i=1;i<=NF;i++){printf("%s ",\$i); if(i%20==0){printf("\\n")}}printf("\\n")}'>> $out_mailfile`;
        `echo END >> $out_mailfile`;

        if ($stage eq "all"){ # we do not send the result for the merged tarball
            next;
        }

        foreach my $to_email(@to_email_list)
        {
            my $tagfile = "$WORKDIR/proq2/$folder/casp_prediction_emailed.$to_email";

            my $prediction_file = "$WORKDIR/proq2/$folder/pcomb.mail";

            next if (! -e $prediction_file);

            my $emailed_prediction_file = "$WORKDIR/proq2/$folder/pcomb.mail.$to_email";
            my $isSendMail = 1;
            #if no change has been made to prediction_file, set isSendMail to false
            if (-e $emailed_prediction_file){
                my $diff = `diff $prediction_file $emailed_prediction_file`;
                if ($diff eq "" ){
                    $isSendMail = 0;
                }
            }

            if ($isSendMail){
                my $title = $casp_target_id;
                print "mutt -s \"$title\" \"$to_email\"  < $prediction_file"."\n";
                `mutt -s \"$title\" \"$to_email\"  < $prediction_file`;
                `/bin/cp -f $prediction_file $emailed_prediction_file`;
                $date = localtime();
                `echo $date >>  $tagfile`;
            }
        }
    }
    chdir($rundir);
}
sub read_QA{#{{{
    my $file=shift;
    my $start=0;
    my $key="";
    my $global_quality=0;
    my @local_quality=();
    my %global_quality=();
    my %local_quality=();
    open(FILE,$file);
    while(<FILE>)
    {
        if($start)
        {
            chomp;
            my @temp=split(/\s+/);
            last if(not(defined($temp[0])));
            #if($temp[0]=~/[A-Z]/ && length($temp[0])>1)
            # bug solved in Read_QA, 2014-05-06, model name may contains only
            # lower letter change [A-Z] to [A-Za-z]
            if($temp[0]=~/[A-Za-z]/ && length($temp[0])>1)
            {
                if(scalar(@local_quality)>0)
                {
                    $global_quality{$key}=$global_quality;
                    @{$local_quality{$key}}=@local_quality;
                }
                last if(/^END/);
                $key=$temp[0];
                #$key=~s/\.pdb$//g;
                $global_quality=$temp[1];
                @local_quality=@temp[2..$#temp];
            }
            else
            {
                @local_quality=(@local_quality,@temp);
            }
        }
        $start=1 if(/^QMODE 2/);
    }

    
    #foreach my $key(keys(%global_quality))
    #{
    #   my $size=scalar(@{$local_quality{$key}});
    #   print "$key $global_quality{$key} $size\n";
    #   
    #}
    return({%global_quality},{%local_quality});
}#}}}

# sub d2S#{{{
# {
#     my $rmsd=shift;
#     return 1/sqrt(1+$rmsd*$rmsd/9);
# }#}}}

sub d2S{  #changed on 2014-05-15 according to bjorn
    my $rmsd=shift;
    return 1/(1+$rmsd*$rmsd/9);
}

sub S2d#{{{
{
    my $S=shift;
    my $d0=3;
    my $rmsd=0;
    $rmsd=15; # for CASP we cap the distance at 15 angstroms
    if($S>0.03846) # this is the S score for 15 angstroms
    {
        if($S>=1)
    {    
        $rmsd=0;
    }
    else
    {
        $rmsd=sqrt(1/$S-1)*$d0;
    }
    }
    return $rmsd;
}#}}}
