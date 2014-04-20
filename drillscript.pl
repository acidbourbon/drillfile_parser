#!/usr/bin/perl -w

use strict;
use Device::SerialPort;
use Time::HiRes;

# the drillfile
my $drillfile="./project.drl";

my $dont_turn=0;
my $mirror_x = -1; # 1 => no mirror, -1 => mirrored horiz
my $mirror_y = 1; # 1 => no mirror, -1 => mirrored vert

my $tolerance = 1; # mm , die if calibration fails 


# drillfiles have to be generated with option "mirrored y axis"
# otherwise the coordinates in the drillfile are not the same
# as in the CAD view

# mirror either x or y coordinate when you drill a PCB backside
# (PCB backside up)
# you still have to got to the top left and bottom right hole
# in the respectively mirrored view!

# I recommend: Take your PCB from the front side, flip it on the vertical
# axis, so top is still top. Select mirror_x = -1. Drill, enjoy!


# array of hashes, each hash contains info of
# one hole

# the serial port object
my $port;
# the address of the drill control tty
my $ser_dev = "/dev/ttyACM0";


my @drillholes = slurp_drillfile();






# for my $entry (@drillholes) {
# 
# print "Tool: ".$entry->{"tool"}."\n";
# print "Diameter: ".$entry->{"dia"}."\n";
# print "x,y: ".$entry->{"x"}.",".$entry->{"y"}."\n";
# print "\n";
# 
# }


# exit;

# find lowest and highest values in x and y
my ($minX,$minY,$maxX,$maxY);

for my $entry (@drillholes) {

  if(defined($minX)) {
    if ($entry->{"x"} < $minX) {
      $minX = $entry->{"x"};
    }
  } else {
    $minX = $entry->{"x"};
  }
  
  if(defined($minY)) {
    if ($entry->{"y"} < $minY) {
      $minY = $entry->{"y"};
    }
  } else {
    $minY = $entry->{"y"};
  }
  
  if(defined($maxX)) {
    if ($entry->{"x"} > $maxX) {
      $maxX = $entry->{"x"};
    }
  } else {
    $maxX = $entry->{"x"};
  }
  
  if(defined($maxY)) {
    if ($entry->{"y"} > $maxY) {
      $maxY = $entry->{"y"};
    }
  } else {
    $maxY = $entry->{"y"};
  }
  
}

print "minX: ".$minX."\n";
print "minY: ".$minY."\n";
print "maxX: ".$maxX."\n";
print "maxY: ".$maxY."\n";

# find the two drills close to the top left and the bottom right corners

my $topleftindex = 0;
my $topleftdistance_hs;
my $bottomrightindex = 0;
my $bottomrightdistance_hs;

for my $i ( 0 .. $#drillholes ) {
  my $holeX = $drillholes[$i]{"x"};
  my $holeY = $drillholes[$i]{"y"};
  my $topleftdistance = abs( distance($holeX,$holeY,$minX,$minY) );
  my $bottomrightdistance = abs( distance($holeX,$holeY,$maxX,$maxY) );
  
  if (defined($topleftdistance_hs)) {
    if ($topleftdistance < $topleftdistance_hs) {
      $topleftdistance_hs = $topleftdistance;
      $topleftindex = $i;
    }
  } else {
      $topleftdistance_hs = $topleftdistance;
      $topleftindex = $i;
  }
  
  if (defined($bottomrightdistance_hs)) {
    if ($bottomrightdistance < $bottomrightdistance_hs) {
      $bottomrightdistance_hs = $bottomrightdistance;
      $bottomrightindex = $i;
    }
  } else {
      $bottomrightdistance_hs = $bottomrightdistance;
      $bottomrightindex = $i;
  }
  
  print "hole#$i x:$holeX y:$holeY tld:$topleftdistance brd:$bottomrightdistance\n";
  print "tld highscore: $topleftdistance_hs, brd highscore: $bottomrightdistance_hs\n";
}



# these are the indices of the topleft and bottomright drillholes

print "topleftindex: $topleftindex\n";
print "bottomrightindex: $bottomrightindex\n";


# transformation vectors

# a   = -a =>  0  = Q =>   0  = +c =>  c 
# b   = -a =>  p  = Q =>   q  = +c =>  d

# a and b are reference vectors (coordinates) in the drillfile
# c and d are the corresponding reference points on the 


my $a1 = $drillholes[$topleftindex]{"x"};
my $a2 = $drillholes[$topleftindex]{"y"};

my $b1 = $drillholes[$bottomrightindex]{"x"};
my $b2 = $drillholes[$bottomrightindex]{"y"};

print "topleft: $a1,$a2, bottomrgiht: $b1,$b2\n";

## now drive to the points! and you will retrieve: 

init_port();

my $dummy="";
# 
# while(not($dummy =~ /q/)){ 
# my ($c1,$c2) = get_coordinate();
# print "position : $c1 $c2\n";
# print "repeat or continue? (q)";
# $dummy = <STDIN>;
# $dummy = <STDIN>;
# }

print "\n\n";
print "move to top left drill hole and press enter\n";
$dummy = <STDIN>;



# my $c1 = $a1;
# my $c2 = $a2;

my ($c1,$c2) = get_coordinate();
$dummy = <STDIN>;
($c1,$c2) = get_coordinate();

print "vector c : $c1 $c2\n";

print "good, now move to bottom right drill hole and press enter\n";
$dummy = <STDIN>;

# my $d1 = $b1;
# my $d2 = $b2;

my ($d1,$d2) = get_coordinate();
$dummy = <STDIN>;
($d1,$d2) = get_coordinate();


print "vector d : $d1 $d2\n";

my $p1 = $b1-$a1;
my $p2 = $b2-$a2;

print "p: $p1,$p2\n";


my $q1 = $d1-$c1;
my $q2 = $d2-$c2;
print "q: $q1,$q2\n";

# this is the place where we make it a pure
# rotation / translateon

# we require that the corrected vector q has the same
# length as p, so the transformation matrix is 
# a pure rotation

my $q_len = distance($q1,$q2,0,0);
my $p_len = distance($p1,$p2,0,0);
my $pq_diff = abs($p_len - $q_len);

printf ("p_len : %3f mm, q_len : %3f mm\n",$p_len,$q_len);
printf ("Calibration residuum: %3f mm\n",$pq_diff);

die "calibration fail, maybe wrong drl file?\n" if ($pq_diff > $tolerance);




my $q_hat_1 = $q1/$q_len;
my $q_hat_2 = $q2/$q_len;

# calculate midpoint between c and d

my $cd1 = ($c1 + $d1)/2;
my $cd2 = ($c2 + $d2)/2;

# calculate corrected c and d 

$c1 = $cd1 - $q_hat_1*$p_len/2;
$c2 = $cd2 - $q_hat_2*$p_len/2;


$d1 = $cd1 + $q_hat_1*$p_len/2;
$d2 = $cd2 + $q_hat_2*$p_len/2;

# corrected q vector
$q1 = $d1-$c1;
$q2 = $d2-$c2;

# now we can calculate sine and cosine coefficients

my $cos_alpha = ($p1*$q1+$p2*$q2)/($p1**2+$p2**2);
my $sin_alpha = ($p2*$q1-$p1*$q2)/($p1**2+$p2**2);

if($dont_turn){
  $cos_alpha = 1;
  $sin_alpha = 0;
}

print "cos_alpha : $cos_alpha, sin_alpha : $sin_alpha\n";
print "sum of squares (should be 1): ".($cos_alpha**2+$sin_alpha**2)."\n";

print "\n\n";

print "okay let us now drive to every hole!";
$dummy = <STDIN>;

for my $i ( 0 .. $#drillholes ) {
  my $holeX = $drillholes[$i]{"x"};
  my $holeY = $drillholes[$i]{"y"};
  
  my ($tableX,$tableY) = transform_to_table($holeX,$holeY);
  
  print "hole # $i:\n";
  print "Tool: ".$drillholes[$i]{"tool"}."\n";
  print "Diameter: ".$drillholes[$i]{"dia"}."\n";
  print "x,y: ".$drillholes[$i]{"x"}.",".$drillholes[$i]{"y"}."\n";
  print "x',y' (on table) $tableX , $tableY\n";
  print "\n";
  
  communicate("gx$tableX");
  communicate("gy$tableY");
  
  $dummy = <STDIN>;
  if ($dummy =~ /q/i) {
    exit;
  }
}

# my ($t1,$t2) = transform_to_table(147,69);
# print "t: $t1 , $t2\n";






# my ($t1,$t2) = get_coordinate(); 
# 
# print "t: $t1 , $t2\n";
# 
# $t1+=22;
# $t2+=22;
# print "t: $t1 , $t2\n";
# 

















sub get_coordinate {
  my $answer = communicate("");
#   for (1..10) {
#     Time::HiRes::sleep(.01);
#     $answer =  communicate("");
#   }
  $answer =~ m/x_pos:([\+\-\s\d\.]+)y_pos:([\+\-\s\d\.]+)/;
  my $x = $1;
  my $y = $2;
  $x =~ s/\s//g;
  $y =~ s/\s//g;
  return ($x,$y);
}


sub communicate {

  my $command = $_[0];



  $port->are_match("\n");
  $port->lookclear;
  $port->write("\n");
  while(my $a = $port->lookfor) {
    print "#$a\n";
  }
  $port->lookclear; 
  $port->write("$command\n");



  # read what has accumulated in the serial buffer
  # do 1 seconds of polling
  for (my $i = 0; ($i<100) ;$i++) {
#     print $i."\n";
    while(my $a = $port->lookfor) {
#       print $a;
      $a =~ s/[\r\n]//g;
      if( $a =~ m/x_pos.+y_pos/) { ## discard the standard error string
        return $a;
      }

    } 
      Time::HiRes::sleep(.01);

  }


  return "no answer";
  

}







sub transform_to_table {
  my $x1 = shift;
  my $x2 = shift;
  
  
  my $y1 = $cos_alpha*($x1-$a1)+$sin_alpha*($x2-$a2)+$c1;
  my $y2 = -$sin_alpha*($x1-$a1)+$cos_alpha*($x2-$a2)+$c2;
  return ($y1,$y2);

}


sub distance {
  my $x1 = shift;
  my $y1 = shift;
  my $x2 = shift;
  my $y2 = shift;
  
  return sqrt(($x2-$x1)**2+($y2-$y1)**2);

}

sub init_port {
  
  my $baudrate;
  if( defined ($_[0]) ) {
    $baudrate = $_[0];
  } else {
    $baudrate = 9600;
  }
    
  # talk to the serial interface

  $port = new Device::SerialPort($ser_dev);
  unless ($port)
  {
    print "can't open serial interface $ser_dev\n";
    exit;
  }

  $port->user_msg('ON'); 
  $port->baudrate($baudrate); 
  $port->parity("none"); 
  $port->databits(8); 
  $port->stopbits(1); 
  $port->handshake("xoff"); 
  $port->write_settings;

}


sub slurp_drillfile {

my @drillholes;
open(LESEN,$drillfile)
  or die "Fehler beim oeffnen von : $!\n";
  
my $current_tool_no;
my %drilldias;

  while(defined(my $i = <LESEN>)) {


    if ( $i =~ /^(T\d+)C(\d+.\d+)/ ) {
  #     print "found tool T".$1." with diameter ".$2."mm\n";
      $drilldias{$1} = $2;
    }
    
    if ( $i =~ /^(T\d+)$/ ) {
      $current_tool_no = $1;
    }
    
    if ( $i =~ /^X(\d+.\d+)Y(\d+.\d+)/ ) {
  #     print "Tool $current_tool_no , $1 , $2\n";
      my $this_x = $1 * $mirror_x;
      my $this_y = $2 * $mirror_y;
      push(@drillholes,{tool => $current_tool_no, x => $this_x, y => $this_y, dia => $drilldias{$current_tool_no}});
    }
    

  }
  return @drillholes;

}
