#!/usr/bin/perl -w

use strict;
use Net::Pcap;
use NetPacket::Ethernet qw( :types :strip );
use NetPacket::IP qw( :protos :strip :versions );
use NetPacket::UDP qw( :strip );
use NetPacket::ICMP qw( :strip :types );
use Getopt::Std;
use Socket qw( inet_aton );

# global variables
our %bloom_measurements      = ();
our %bloom_clock     = ();
our %bloom_counter   = ();
our $num_clks_per_bu = 2875000;
our $gran            = 1000;

sub udp_debug {
   my $udp_packet = shift;
   my $udp_dgram = NetPacket::UDP->decode($udp_packet);

   print "src port: ",$udp_dgram->{src_port},", dst port: ",$udp_dgram->{dest_port},"\n";
   
   #the len of UDP is 8bytes
   my $pld_len_in_bytes = $udp_dgram->{len} - 8;  

   my $payload = $udp_dgram->{data};

   my $zero = unpack("H12",substr($payload,0,6));

   my $NUM_BLOOM_IN_PACKET = 10;
   my $bloom_key;
   my ($src_oct_1,$src_oct_2,$src_oct_3,$src_oct_4);
   my ($dst_oct_1,$dst_oct_2,$dst_oct_3,$dst_oct_4);
   my ($port1,$port2);
   my $offset=0;
   my $data_length=16;
   my ($measurement1, $measurement2);
   my $up_measurement;
   my $milicount;
   my ($src_ip,$dst_ip);

   for(my $i=0; $i < $NUM_BLOOM_IN_PACKET; $i++){
      $offset = 6+$data_length*($i);
      $bloom_key = unpack("H24",substr($payload,$offset,12));

      $src_oct_1 = hex(unpack("H2",substr($payload,$offset,1)));
      $src_oct_2 = hex(unpack("H2",substr($payload,$offset+1,1)));
      $src_oct_3 = hex(unpack("H2",substr($payload,$offset+2,1)));
      $src_oct_4 = hex(unpack("H2",substr($payload,$offset+3,1)));

      $dst_oct_1 = hex(unpack("H2",substr($payload,$offset+4,1)));
      $dst_oct_2 = hex(unpack("H2",substr($payload,$offset+5,1)));
      $dst_oct_3 = hex(unpack("H2",substr($payload,$offset+6,1)));
      $dst_oct_4 = hex(unpack("H2",substr($payload,$offset+7,1)));

      $port1 = unpack("n",substr($payload,$offset+8,2));
      $port2 = unpack("n",substr($payload,$offset+10,2));

      $milicount     = unpack("H4",substr($payload,$offset+12,2));
      $measurement1  = unpack("H2",substr($payload,$offset+14,1));
      $measurement2  = unpack("H2",substr($payload,$offset+15,1));

      $src_ip = sprintf("%0d.%0d.%0d.%0d",$src_oct_1,$src_oct_2,$src_oct_3,$src_oct_4);
      
      $dst_ip = sprintf("%0d.%0d.%0d.%0d",$dst_oct_1,$dst_oct_2,$dst_oct_3,$dst_oct_4);

      printf "%s:%d -> %s:%d ... $measurement1:$measurement2\n",$src_ip,$port1,$dst_ip,$port2;
      
      if(hex($measurement1) == hex($measurement2) && hex($measurement1) != 0x0f){
         if(defined ($bloom_measurements{$bloom_key})) {
            $bloom_measurements{$bloom_key} += hex($measurement1);   
         } else {
            $bloom_measurements{$bloom_key} = hex($measurement1);   
         }

         if(defined ($bloom_counter{$bloom_key})) {
            $bloom_counter{$bloom_key} += 1;   
         } else {
            $bloom_counter{$bloom_key} = 1;
         }

         if(defined ($bloom_clock{$bloom_key})) {
            $bloom_clock{$bloom_key} +=
            ($num_clks_per_bu*hex($measurement1)+hex($milicount)*$gran)-0.5*$num_clks_per_bu;  
         } else {
            $bloom_clock{$bloom_key} = 
            ($num_clks_per_bu*hex($measurement1)+hex($milicount)*$gran)-0.5*$num_clks_per_bu;
         }
      }
      else {
         printf "Erro em medição: %s\n",hex($measurement1);
      }

   }

}

sub icmp_debug {
   my $icmp_packet = shift;
   my $icmp_dgram = NetPacket::ICMP->decode($icmp_packet);
   print "Type: ",$icmp_dgram->{type},", Code: ",$icmp_dgram->{code},", ";
   print "Chksum: ",$icmp_dgram->{cksum},"\n";
}

sub ip_debug {
   my $ip_packet = shift;
   my $ip_dgram = NetPacket::IP->decode($ip_packet);

   print "src ip: ",$ip_dgram->{src_ip},", dst ip: ",$ip_dgram->{dest_ip}," len: ",$ip_dgram->{len},"\n";

   if($ip_dgram->{proto} == NetPacket::IP::IP_PROTO_UDP){
      udp_debug($ip_dgram->{data});
   } elsif ($ip_dgram->{proto} == NetPacket::IP::IP_PROTO_TCP){
      print "TCP\n";

   } elsif ($ip_dgram->{proto} == NetPacket::IP::IP_PROTO_ICMP){
      icmp_debug($ip_dgram->{data});
   } else {
      print "IP Packet is neither TCP or UDP\n";
   }

}

sub got_a_packet {
   my ($args, $header, $packet) = @_;
   my $frame = NetPacket::Ethernet->decode( $packet );
   print("src MAC: $frame->{src_mac} ");
   print("dest MAC: $frame->{dest_mac}\n");

   #unless ($frame->{type} == NetPacket::Ethernet::ETH_TYPE_IP){
   #   die "Packet is not a IP packet\n";
   #}
   foreach my $name (sort keys %{$header}){
      print "$name : $header->{$name}\n";
   }

   if ($frame->{type} == NetPacket::Ethernet::ETH_TYPE_IP){
      ip_debug($frame->{data});
   } elsif ($frame->{type} == NetPacket::Ethernet::ETH_TYPE_ARP){
      print "ARP\n";
   } else {
      print "Another protocol\n";
   }

}

my $err = '';
my $dev = 'nf2c0';
my $number_of_pkts = -1; # loop forever

# parsers the command line
my %options = ();
getopts('c:hi:f:n:',\%options);

die "-c <num clks until shift>\n-f <filter EXPR>\n-i <iface>\n-n <number of packets to receive>\n-h for help\n\n" if defined $options{h};

$dev = $options{i} if (defined $options{i});
$number_of_pkts = $options{n} if (defined $options{n});

# it sets the number of clk per bucket shift
$num_clks_per_bu = $options{c} if (defined $options{c});

my $is_promisc = 1;

my $pcap = Net::Pcap::pcap_open_live($dev,1500,$is_promisc,0,\$err) or die "Cant open device $dev: $err\n";

# parsers filter options if there is
my $filter;

if(defined $options{f}){
   my $netmask = inet_aton "255.255.255.0";

   $err = Net::Pcap::pcap_compile($pcap, \$filter, $options{f}, 1, Net::Pcap::PCAP_IF_LOOPBACK);#$netmask);
   if($err == -1){
      die "Unable to compile the filter message\n";
   }
   Net::Pcap::pcap_setfilter($pcap, $filter);
}

Net::Pcap::pcap_loop($pcap,$number_of_pkts,\&got_a_packet,'');

Net::Pcap::pcap_close($pcap);

my $key;
my @keys = keys %bloom_measurements;
foreach $key (@keys) {
   printf "----- bloom{$key} -----\nNo. pacotes: %f\nMedia buckets: %f\nMedia (em ms): %f\n\n", 
      $bloom_counter{$key},$bloom_measurements{$key}/$bloom_counter{$key},$bloom_clock{$key}*8e-9*1e3/$bloom_counter{$key};
}
