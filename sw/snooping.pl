#!/usr/bin/perl -w

use strict;
use Net::Pcap;
use NetPacket::Ethernet qw( :types :strip );
use NetPacket::IP qw( :protos :strip :versions );
use NetPacket::UDP qw( :strip );
use NetPacket::ICMP qw( :strip :types );

our %bloom_hash = ();

sub udp_debug {
   my $udp_packet = shift;
   my $udp_dgram = NetPacket::UDP->decode($udp_packet);

   print "src port: ",$udp_dgram->{src_port},", dst port: ",$udp_dgram->{dest_port},"\n";
   
   #the len of UDP is 8bytes
   my $pld_len_in_bytes = $udp_dgram->{len} - 8;  

   my $payload = $udp_dgram->{data};

   #my ($zero,$ip1,$ip2,$p1,$p2,$measurement) = unpack("S3 L L S S L",$payload);
   my $zero = unpack("H12",substr($payload,0,6));

   my $NUM_BLOOM_IN_PACKET = 4;
   my $bloom_key;
   my ($src_oct_1,$src_oct_2,$src_oct_3,$src_oct_4);
   my ($dst_oct_1,$dst_oct_2,$dst_oct_3,$dst_oct_4);
   my ($port1,$port2);
   my $offset=0;
   my $data_length=16;
   my $measurement;
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

      $measurement = unpack("H8",substr($payload,$offset+12,4));

      $src_ip = sprintf("%0d.%0d.%0d.%0d",$src_oct_1,$src_oct_2,$src_oct_3,$src_oct_4);

      $dst_ip = sprintf("%0d.%0d.%0d.%0d",$dst_oct_1,$dst_oct_2,$dst_oct_3,$dst_oct_4);

      printf "%s:%d -> %s:%d ... $measurement\n",$src_ip,$port1,$dst_ip,$port2;
   
      $bloom_hash{$bloom_key} += $measurement;   
      printf "%d\n", $bloom_hash{$bloom_key};

   }

   #printf "%d %d\n",unpack("n",substr($payload,16,2)),unpack("n",substr($payload,14,2));

   my $key;
   my @keys = keys %bloom_hash;
   foreach $key (@keys) {
      print "bloom{$key}: $bloom_hash{$key}\n";
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

   print "src ip: ",$ip_dgram->{src_ip},", dst ip: ",$ip_dgram->{dest_ip},"\n";

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
my $dev = 'eth0';

$dev = $ARGV[0] if (defined $ARGV[0]);
print "$dev\n";

my $is_promisc = 1;

my $pcap = Net::Pcap::pcap_open_live($dev,1500,$is_promisc,0,\$err) or die "Cant oopen device $dev: $err\n";

my $filter;

if(defined $ARGV[1]){
   $err = Net::Pcap::pcap_compile($pcap, \$filter, $ARGV[1], 1, "255.255.255.0");
   if($err == -1){
      die "Unable to compile the filter message\n";
   }
   Net::Pcap::pcap_setfilter($pcap, $filter);
}


Net::Pcap::pcap_loop($pcap,-1,\&got_a_packet,'');

pcap_close($pcap);