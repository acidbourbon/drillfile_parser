# drillfile_parser
A perl script that "eats" drl files (containing drill coordinates) and moves the PCB underneath the drill. Software counterpart of the mini_CNC microcontroller project.

see detailed information to the project at:
https://acidbourbon.wordpress.com/2015/02/01/semi-automated-drill-press-table-for-pcb-manufacture/

software dependencies:

Device::SerialPort (perl module)

on debian based Linux distros you can install it with

````bash
sudo apt-get install libdevice-serialport-perl
````

Alternatively you can use CPAN (on any decent distro)

````bash
sudo cpan Device::SerialPort
````

