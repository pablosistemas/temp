#!/usr/bin/perl -w

use IO::Socket;
use Socket qw ( PF_INET SOCK_STREAM pack_sockaddr_in inet_aton );
use strict;
use Getopt::Std;
use Thread qw ( :DEFAULT async yield );

use constant MAX_RECV_LEN => 65536;

sub read_message {
   my $sock = shift;
   my $data;
   my $from_who;
   while(1){
      $from_who = recv( $sock, $data, MAX_RECV_LEN, 0 );
      if ( $from_who ) {
         my ( $the_port, $the_ip ) = sockaddr_in ( $from_who );
         warn "Received from $the_ip:$the_port => $data\n";
      } else {
         warn "problem with recv: $data\n";
      }
   }
   close $sock;
}

# default vars
my $from_ip       = '127.0.0.1';
my $to_ip         = '127.0.0.1';
my $from_port     = 5555;
my $to_port       = 6666;
my $server_mode   = 0;
my $repeat        = 1;
my $message       = 'hello';
my %options       = ();

# parsers the message
getopts( 'ha:b:c:d:sm:n:',\%options );

die "-a <from ip>\n-b <to ip>\n-c <from port>\n-d <to port>\n-m <'message'>\n-n <send the message n times>\n-s for server mode (default is client mode)\n-h for help\n" 
      if defined $options{h};

$from_ip       = $options{a} if defined $options{a};
$to_ip         = $options{b} if defined $options{b};
$from_port     = $options{c} if defined $options{c};
$to_port       = $options{d} if defined $options{d};
$message       = $options{m} if defined $options{m};
$repeat        = $options{n} if defined $options{n};
$server_mode   = 1 if defined $options{s};

my $bin_fip    = inet_aton ( $from_ip );
my $bin_tip    = inet_aton ( $to_ip );

my $sock;
my $proto      = getprotobyname ('tcp');
socket ($sock, PF_INET, SOCK_STREAM, $proto) or die "ERROR socket\n";
#setsockopt ( $sock, SOL_SOCKET, SO_REUSEADDR, 1 ) or die "ERROR setsocketopt\n";

my $local_addr;
my $out_addr;

if ($server_mode) {
   $local_addr = sockaddr_in( $to_port,INADDR_ANY );
   $out_addr   = sockaddr_in( $from_port,$bin_fip );
   bind ($sock, $local_addr ) or die "ERROR in bind\n";
   listen ($sock, SOMAXCONN) or die "ERROR listen\n";
   warn "Server starting up on port: $to_port\n";

   my $from_who;
   my $newsock;
   my $t;
   while($from_who = accept( $newsock, $sock )){
      $t = Thread->new(\&read_message, $newsock );
      warn "Accepted new connection\n\n";
   }

} else {
   $out_addr      = sockaddr_in( $to_port,$bin_tip );
   $local_addr    = sockaddr_in( $from_port,$bin_fip );
   bind ($sock, $local_addr ) or die "ERROR in bind\n";
   connect ($sock, $out_addr) or die "ERROR connection\n";
   for (my $i=0; $i < $repeat; $i++){
      send ($sock, $message, 0);
      printf "sending message $i\n";
      sleep(1);
   }
}

close $sock;
