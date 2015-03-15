#!/usr/bin/perl -w

use strict;
use Device::SerialPort;
use Time::HiRes;
use Data::Dumper;
use Getopt::Long;

use SVG;

my $help=0;
my $configFile=0;
my $invx;
my $invy;


sub print_help{
print <<EOF;  
drillscript.pl -f <cadfile.drl> --tty <address> [OPTIONS]

drillscript parses DRL files and moves the proxxon x-y-table underneath the drill
to pass by all drill holes.

options:

-h, --help              print this help message
-f, --file <filename>   the cad file to be processed
--tty <address>         the address of the COM port
                        (if left out /dev/ttyACM0 is used)
--invx                  invert x axis
--invy                  invert y axis
--tolerance <number>    set calibration tolerance
                        (default = 1 mm)
--onesize <number>      set to drill diameter [mm] to 
                        treat all drill holes as if they had
                        given diameter
--noturn                calibrate, but don't rotate
-v, --verbose           verbose output
                        
example:

drillscript.pl -f PCB_Project.drl --tty /dev/ttyACM0 --onesize 0.8 

hints:

mirror either x or y coordinates when you drill a PCB backside
(PCB backside up)
you still have to got to the top left and bottom right hole
in the respectively mirrored view!
EOF
exit;
}


#######################################
############   options   ##############
#######################################

# the drillfile
my $drillfile;

my $dont_turn= 0; # 1 => do not perform turning transformation,
# x and y axis of project are parallel to x and y on the table

my $mirror_x = 1; # 1 => no mirror, -1 => mirrored horiz (-1 for PCB backside facing drill)
my $mirror_y = 1; # 1 => no mirror, -1 => mirrored vert

my $tolerance = 1; # mm , die if calibration residual (p-q) is bigger than tolerance

my $oneSize = 0; # mm , if set to non-zero, all drill diameters will be set to
# this value

my $visit_intermediates = 1; # activate improved moving algorithm
my $stray_factor = sqrt(2)*1.05;

# can enter here calibration values for debug:
# my ($c1,$c2) = (-6.500,-21.125);
# my ($d1,$d2) = (+13.875,+14.625);

my $verbose = 0;

# the address of the drill control tty
my $ser_dev = "/dev/ttyACM0";

# drillfiles have to be generated with option "mirrored y axis"
# otherwise the coordinates in the drillfile are not the same
# as in the CAD view

# mirror either x or y coordinate when you drill a PCB backside
# (PCB backside up)
# you still have to got to the top left and bottom right hole
# in the respectively mirrored view!

# I recommend: Take your PCB from the front side, flip it on the vertical
# axis, so top is still top. Select mirror_x = -1. Drill, enjoy!


Getopt::Long::Configure(qw(gnu_getopt));
GetOptions(
           'help|h' => \$help,
           'verbose|v' => \$verbose,
           'config|c=s' => \$configFile,
           'file|f=s'   => \$drillfile,
           'file|f=s'   => \$drillfile,
           'invx'       => \$invx,
           'invy'       => \$invy,
           'noturn'     => \$dont_turn,
           'tolerance=s'=> \$tolerance,
           'onesize=s'  => \$oneSize,
           'help|h'     => \$help,
           'verbose'    => \$verbose,
           'tty=s'      => \$ser_dev
          );

$mirror_x *= -1 if $invx;
$mirror_y *= -1 if $invy;


print_help() if $help;
print_help() unless $drillfile;


# array of hashes, each hash contains info of
# one hole

# the serial port object
my $port;


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

holes_pattern_svg();

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




# my $c1 = $a1;
# my $c2 = $a2;
# unless(defined($c1) and defined($c2) and defined($d1) and defined ($d2)) {

print "move to top left drill hole and press enter\n";
$dummy = <STDIN>;
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
# }


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



my %absolved_holes;
my @closest_drillholes;


for my $i ( 0 .. $#drillholes ) {

  unless ( $absolved_holes{$i} ) {
    go_hole($i);
    $absolved_holes{$i} = 1;
    
    last if ( scalar(keys %absolved_holes) == $#drillholes ); # break the loop if job is done, all holes have been drilled
    
    # check if there are some intermediate holes you could drill
    
    my $current_index = $i; # could be bottom right hole_distance
    my $next_index = $i + 1;
    my $intermediate_index;
    my $intermediate_found = 0;
    
    do {
      @closest_drillholes = 
	sort { hole_distance($a->{"number"},$current_index) <=> hole_distance($b->{"number"},$current_index) } @drillholes;
# 	print Dumper @closest_drillholes if $verbose;
      
      $intermediate_found = 0;
      
      for my $intermediate_hole (@closest_drillholes){
        $intermediate_index = $intermediate_hole->{"number"};
        print "probing intermediate index $intermediate_index\n" if $verbose;
	next if ($absolved_holes{$intermediate_index});
	print "Test 1 passed: not in absolved holes\n" if $verbose;
	my $cur_next_dist = hole_distance($current_index,$next_index);
	my $cur_inter_dist = hole_distance($current_index,$intermediate_index);
        print "cur_next_dist:$cur_next_dist\ncur_inter_dist:$cur_inter_dist\n" if $verbose;
	last if ($cur_inter_dist >= $cur_next_dist); # break if no holes closer than "next" hole
	print "Test 2 passed: intermediate closer than next hole\n" if $verbose;
	my $inter_next_dist = hole_distance($intermediate_index,$next_index);
        print "inter_next_dist:$inter_next_dist\n" if $verbose;
	last if ($inter_next_dist >= ($cur_next_dist*$stray_factor)); # break if distance from intermediate to next is longer than
	print "Test 3 passed: inter_next dist < stray_factor*cur_next_dist\nintermediate_found!\n" if $verbose;
	  # from current to next
	# if I get here, I should have found a worthy intermediate hole
	$intermediate_found = 1;
	last;
      }
      
      if ($intermediate_found){
	go_hole($intermediate_index);
	$absolved_holes{$intermediate_index} = 1;
	$current_index = $intermediate_index;
      }
      
    } while ($intermediate_found);


    
    
 
    
  }

}




# my ($t1,$t2) = transform_to_table(147,69);
# print "t: $t1 , $t2\n";




sub hole_distance {
# give me two indices
  my $n = shift;
  my $m = shift;
  
  return distance( $drillholes[$n]{"x"},$drillholes[$n]{"y"},$drillholes[$m]{"x"},$drillholes[$m]{"y"});

}

# my ($t1,$t2) = get_coordinate(); 
# 
# print "t: $t1 , $t2\n";
# 
# $t1+=22;
# $t2+=22;
# print "t: $t1 , $t2\n";
# 




sub go_hole {

  my $i = shift;
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
my $hole_number= 0;

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
      if ($oneSize) {
	push(@drillholes,{tool => 1, x => $this_x, y => $this_y, dia => $oneSize, number => $hole_number++});
      } else {
	push(@drillholes,{tool => $current_tool_no, x => $this_x, y => $this_y, dia => $drilldias{$current_tool_no}, number => $hole_number++});
      }
    }
    

  }
  return @drillholes;

}


sub holes_pattern_svg {

  my $scale = 12; # pixel per mm
  my $margin = 10; # mm
  my $legend_width = 50; #mm
  my $legend_padding = 5;
  
  my $pic_width  = ($maxX-$minX+2*$margin +$legend_width)*$scale;
  my $pic_height = ($maxY-$minY+2*$margin)*$scale;
  
  my $legend_x = $maxX-$minX+2*$margin + $legend_padding;
  my $legend_y = $legend_padding;
  my $legend_spacing = 5;
  
  my $tools_dias;
  
  my @colors = ( "red","blue","purple","green","orange","grey","yellow");
  
  
  my $svg_file = "./holes.svg";
  
  my $svg = SVG->new(
        -printerror => 1,
        -raiseerror => 0,
        -indent     => '  ',
        -docroot => 'svg', #default document root element (SVG specification assumes svg). Defaults to 'svg' if undefined
        #-sysid      => 'abc', #optional system identifyer 
        #-pubid      => "-//W3C//DTD SVG 1.0//EN", #public identifyer default value is "-//W3C//DTD SVG 1.0//EN" if undefined
        #-namespace => 'mysvg',
        -inline   => 1,
        id          => 'document_element',
    width => $pic_width,
    height => $pic_height,
  );
  
  my $scaler = $svg->group(
      transform => "scale($scale)"
  );
  my $tx = -$minX+$margin;
  my $ty = -$minY+$margin;
  my $translate1 = $scaler->group(
      transform => "translate($tx,$ty)"
    );
  for my $hole (@drillholes) {
    my $tool_number = $hole->{tool};
    $tool_number =~ s/\D//g;
    $tool_number--;
    $tools_dias->{$hole->{tool}} = $hole->{dia};
#     print "$tool_number\n";
     $translate1->circle(
        cx => $hole->{x} ,
        cy => $hole->{y} ,
        r => $hole->{dia}/2 ,
        style=>{
              'stroke'=>'none',
#               'fill'=>'rgb(180,180,180)',
              'fill'=>$colors[$tool_number],
              'stroke-width'=>'0.5',
          }
      );
  }
  
  for my $hole (@drillholes[$topleftindex], @drillholes[$bottomrightindex]){
    my $crosswidth = 2;
    $translate1->line(
         x1=> $hole->{x}-$crosswidth, y1=>$hole->{y},
         x2=> $hole->{x}+$crosswidth, y2=>$hole->{y},
       style=>{
             'stroke'=>'black',
             'fill'=>'none',
             'stroke-width'=> 2/$scale,
         }
    );
    $translate1->line(
         x1=> $hole->{x}, y1=>$hole->{y}-$crosswidth,
         x2=> $hole->{x}, y2=>$hole->{y}+$crosswidth,
       style=>{
             'stroke'=>'black',
             'fill'=>'none',
             'stroke-width'=> 2/$scale,
         }
    );
  
  }
  
  my $text_y = $legend_y;
  for my $tool (sort keys %{$tools_dias}){
    $scaler->text(
      x=>$legend_x+5, y=>$text_y,
      style => 'font-size: 3px',
    )->cdata("$tool: ".$tools_dias->{$tool}." mm");
    print("$tool: ".$tools_dias->{$tool}." mm\n");
    
    my $tool_number = $tool;
    $tool_number =~ s/\D//g;
    $tool_number--;
     $scaler->circle(
        cx => $legend_x ,
        cy => $text_y ,
        r => $tools_dias->{$tool}/2 ,
        style=>{
              'stroke'=>'none',
#               'fill'=>'rgb(180,180,180)',
              'fill'=>$colors[$tool_number],
              'stroke-width'=>'0.5',
          }
      );
      
    $text_y+=$legend_spacing;
  }
  
  if (defined($svg_file)){
    open(SVGFILE, ">".$svg_file) or die "could not open $svg_file for writing!\n";
    # now render the SVG object, implicitly use svg namespace
    print SVGFILE $svg->xmlify;
    close(SVGFILE);
  } else {
    print $svg->xmlify;
  }


}