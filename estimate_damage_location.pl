#!/usr/bin/perl
use strict;
use Getopt::Long qw(GetOptions);
use File::Temp qw(tempfile);

my $error_sentence = "USAGE : perl $0 --mpileup1 mileup_file_from_first_in_pair_read --mpileup2 mileup_file_from_second_in_pair_read --out damage_file_for_R --id library_name \nOPTIONAL :\n --qualityscore 35 (DEFAULT 30)\n --min_coverage_limit 10 (DEFAULT 1)\n --max_coverage_limit 500 (DEFAULT 100) --soft_masked 1 (DEFAULT 1)\n";

# declare the options upfront :
my $file_R1;
my $file_R2;
my $out;
my $generic;
my $QUALITY_CUTOFF = 30;
my $COV_MIN = 1;
my $COV_MAX = 100;
my $SOFT_MASKED=1;
#get options :
GetOptions ("mpileup1=s" => \$file_R1,    # the mpileup file from the first in pair read
	    "mpileup2=s" => \$file_R2, #the mpileup file from the second in pair read
	    "qualityscore=s" => \$QUALITY_CUTOFF,#base quality (either direct from Illumina or recalibrated)
	    "out=s" => \$out,#output file name.
	    "id=s" => \$generic,
	    "min_coverage_limit=s" => \$COV_MIN,
	    "max_coverage_limit=s" => \$COV_MAX,
	    "soft_masked=s" => \$SOFT_MASKED
    ) or die $error_sentence;

#=================================
#if something went wrong in getting the option, notify :
if (!$file_R1 || !$file_R2 || !$out || !$generic) {die $error_sentence}
#=================================

#do not override a file ==========
if(-e $out) { die "File $out Exists, please remove old file or rename output file (--out)"};
#================================= 


my %RC;
$RC{'A_C'} = 'T_G';
$RC{'A_A'} = 'T_T';
$RC{'A_T'} = 'T_A';
$RC{'A_G'} = 'T_C';

$RC{'T_C'} = 'A_G';
$RC{'T_A'} = 'A_T';
$RC{'T_T'} = 'A_A';
$RC{'T_G'} = 'A_C';

$RC{'C_C'} = 'G_G';
$RC{'C_A'} = 'G_T';
$RC{'C_T'} = 'G_A';
$RC{'C_G'} = 'G_C';

$RC{'G_C'} = 'C_G';
$RC{'G_A'} = 'C_T';
$RC{'G_T'} = 'C_A';
$RC{'G_G'} = 'C_C';

$RC{'A_-'} = 'T_-';
$RC{'T_-'} = 'A_-';
$RC{'C_-'} = 'G_-';
$RC{'G_-'} = 'C_-';

$RC{'A_+'} = 'T_+';
$RC{'T_+'} = 'A_+';
$RC{'C_+'} = 'G_+';
$RC{'G_+'} = 'C_+';

#start the main program =============================
my $relative_count_R1 = get_relative_count($file_R1);
my $relative_count_R2 = get_relative_count($file_R2);
#====================================================

#open the output file ====================================
open(OUT, ">$out") or die "can't save result into $out\n";
#=========================================================  


#go over all the mutation possibilities :
foreach my $type (keys %RC)

{
    my $ref = $$relative_count_R1{$type};
    foreach my $position (sort {$a<=>$b} keys %$ref)
    {
	my $value1 = $$relative_count_R1{$type}{$position}{"relative"};
	my $value2 = $$relative_count_R2{$type}{$position}{"relative"};
	my $abs1 = $$relative_count_R1{$type}{$position}{"absolute"};
	my $abs2 = $$relative_count_R2{$type}{$position}{"absolute"};
	if ($$relative_count_R1{$type}{$position}{"relative"} && $$relative_count_R2{$type}{$position}{"relative"})
	{
	   

	    print OUT "$generic\t$type\tR1\t$value1\t$abs1\t$position\n";
	    print OUT "$generic\t$type\tR2\t$value2\t$abs2\t$position\n";
	}
    }
}
close OUT;



sub clean_bases{
    #remove unwanted sign (insertion / deletion (but retain the + and - and remove the first and last base information)
    my ($pattern, $n)=@_; #for example : ,$,,
    #remove the ^ and the next character that correspond to the first base of the read. 
    $pattern =~ s/\^.//g;
    #remove the dollars sign from the last base of the read. 
    $pattern =~ s/\$//g;
    
    if ($pattern =~/\+(\d+)/ || $pattern=~/\-(\d+)/)
    {

	while ($pattern=~/\+(\d+)/)
	{
	    my $size = $1;
	    my $string_to_remove;
	    for(my $i=0; $i<$size; $i++)
	    {
		$string_to_remove = $string_to_remove.".";
	    }
	    $string_to_remove = '.\+\d+'.$string_to_remove;
	    
	    
	    $pattern =~ s/$string_to_remove/\+/;
	    
	}
	while ($pattern=~/\-(\d+)/)
	{
	    my $size = $1;
	    my $string_to_remove;
	    for(my $i=0; $i<$size; $i++)
	    {
		$string_to_remove = $string_to_remove.".";
	    }
	    $string_to_remove = '.\-\d+'.$string_to_remove;
	    
	    
	    $pattern =~ s/$string_to_remove/\-/;
	}


    }
    


    return $pattern;
}





sub get_relative_count {
    my ($file)=@_; 
    my %result;
    my %final;

   
    open (FILE, $file) or die;
    
    while (<FILE>){
	s/\r|\n//g;
	my ($chr,$loc,$ref, $number, $dbases,$q1, $q2, $pos) = split /\t/;
	my $bases = clean_bases($dbases, $number);

	my @tmp = split //, $bases;
	my @poss = split/,/, $pos;
	my $length_mutation = @tmp;

	if ($SOFT_MASKED ==0)
	{
	    #if we do not want to solf masked the repeat : all reference becomes UPPER CASE. 
	    $ref = uc($ref);
	}
	if ($number == $length_mutation && $number >= $COV_MIN && $number <= $COV_MAX && $ref =~/[ACTG]/)
	    #$number == $length_mutation : making sure that the position array and base array are in agreement. 
	    # $number > 0  : position with at least one read
	    #$number < 10  : at 2 M reads across the human genome we are not expecting tp have a high coverage. #!!! be careful of other species.
	    #ref : making sure the position is not soft masked

	{
	    
	    my @base=split (//,$bases);
	    my @qualities =split(//, $q1);
	    for(my $i=0;$i<@base;$i++){

		#given a character $q, the corresponding Phred quality can be calculated with:                                             
                #$Q = ord($q) - 33;  
		my $quality_score = ord($qualities[$i]) - 33;
		
		if ($quality_score > $QUALITY_CUTOFF)
		{
		    
		    my $ch=$base[$i];
		    my $rp = $poss[$i];
		    if($ch=~/[ATCG]/){
			my $type = $ref."_".$ch;
			$result{"type"}{$rp}{$type}++;
			$result{"nt"}{$rp}{$ref}++;
			
		    }
		    elsif($ch=~/[\+\-]/ && $rp > 5){ #this is to remove the artefact of alignment algorithm that add indels (?) at the begining. Should be delt differently. 
                        my $type = $ref."_".$ch;
                        $result{"type"}{$rp}{$type}++;
                        $result{"nt"}{$rp}{$ref}++;

                    }

		    elsif($ch eq "."){
			my $type = $ref."_".$ref;
			$result{"type"}{$rp}{$type}++;
			$result{"nt"}{$rp}{$ref}++;
			
		    }
		}
		
	    }#end the loop
	}
    }
    close FILE;
    my $positions = $result{"type"};
    foreach my $pos (keys %$positions)
    {
	my $mutations = $$positions{$pos};
	foreach my $type (keys %$mutations)
	{
	    my $total_type = $result{"type"}{$pos}{$type};
	    $type =~/(.)\_(.)/;
	    my $total = $result{"nt"}{$pos}{$1};
	    
	    my $value = $total_type/$total;
	    
	    $final{$type}{$pos}{"relative"}=$value;
	    $final{$type}{$pos}{"absolute"}=$total_type;
	}
    }
 
    return(\%final);
}


sub reverse_complement {
        my $dna = shift;

	# reverse the DNA sequence
        my $revcomp = reverse($dna);

	# complement the reversed DNA sequence
        $revcomp =~ tr/ACGTacgt/TGCATGCA/;
        return $revcomp;
}
