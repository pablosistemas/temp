#!/usr/bin/perl -w
# make_pkts.pl
#
# we expect 1st measurement would be strong because the 1st pkt
# is ack of nothing. The number of measurements expected is
# equal to 3*$num_sessions 
#

use NF::PacketGen;
use NF::PacketLib;
use NF::RegAccess;
use lib '/root/netfpga/projects/temp/lib/Perl5';
use aleSimLib;
use SimLib;

use reg_defines_reference_nic;

$delay = '@4us';
$batch = 0;
my $iface = 'nf2c0';

nf_set_environment( { PORT_MODE => 'PHYSICAL', MAX_PORTS => 4 } );

# use strict AFTER the $delay, $batch and %reg are declared
use strict;
use vars qw($delay $batch %reg);

# Prepare the DMA and enable interrupts
SimLib::prepare_DMA('@3.9us');
SimLib::enable_interrupts(0);

my $SRC_IP;
my $DST_IP;
my $SA;
my $DA;

my $length  = 100;
my $ttl     = 30;
my $dst_ip  = 0;
my $src_ip  = 0;
my $seqno   = 0;
my $ackno   = 0;

my $pkt;
my $queue;

my $delay1 = 9000;
my $delay2 = 9000;
my $delay3 = 9000;

$queue = 1;

$length = 102;

my $num_sessions = 15;
my $num_iter = 1;

my $params_ref;

my $eth_len       = 14;
my $ip_total_len  = $length-$eth_len;
my $ip_hdr_len    = 5;
my $data_offset   = 5; #number of 32-bit words in tcp hdr
my $tcp_hdr_len   = $data_offset*4;
my $pld_len = $ip_total_len-($ip_hdr_len*4)-$tcp_hdr_len;

# initializes the sequence and ack numbers
$seqno = int(rand(2**32));
$ackno = int(rand(2**32));

for(my $i = 0; $i < $num_sessions; $i++){
   # cria pacote TCP -> função adicionada na biblioteca

   $SRC_IP = sprintf("192.168.%d.1",$i);
   $DST_IP = sprintf("192.168.%d.1",$i+1);

   $SA = sprintf("00:ca:fe:00:00:%02d",$i);
   $DA = sprintf("00:ca:fe:00:00:%02d",$i+1);
   
   $params_ref = {
      'len' => $length,
      'sa'  => $SA,
      'da'  => $DA,
      'ttl' => $ttl, 
      'src_ip' => $SRC_IP,
      'dst_ip' => $DST_IP,
      'src_port' => 6000,
      'dst_port' => 6001,
      'flags' => (($data_offset<<12)|0x18), #PSH-ACK flag    
      'seqno' => $seqno, 
      'ackno' => $ackno 
   };

   $pkt = aleSimLib::make_IP_TCP_pkt($params_ref);

   NF::PacketGen::nf_packet_in($queue,$length,
      $delay1+int(rand(2**15)),$batch,$pkt);

   NF::PacketGen::nf_expected_dma_data($queue,$length, $pkt);

   # updates sequence number to be ack
   $seqno = $seqno + $pld_len;

   # PSH ACK inverso
   $params_ref = {
      'len' => $length,
      'sa'  => $DA,
      'da'  => $SA,
      'ttl' => $ttl, 
      'src_ip' => $DST_IP,
      'dst_ip' => $SRC_IP,
      'src_port' => 6001,
      'dst_port' => 6000,
      'flags' => (($data_offset<<12)|0x18), #PSH-ACK flag    
      'seqno' => $ackno, 
      'ackno' => $seqno 
   };

   $pkt = aleSimLib::make_IP_TCP_pkt($params_ref);
   NF::PacketGen::nf_packet_in($queue, $length, 
      $delay2+int(rand(2**15)), $batch, $pkt);
   NF::PacketGen::nf_expected_dma_data($queue,$length, $pkt);

   #updates acknowledgement number to be ack
   $ackno = $ackno + $pld_len;
   # ACK
   $params_ref = {
      'len' => $length - $pld_len,
      'sa' => $SA,
      'da' => $DA,
      'ttl' => $ttl, 
      'src_ip' => $SRC_IP,
      'dst_ip' => $DST_IP,
      'src_port' => 6000,
      'dst_port' => 6001,
      'flags' => (($data_offset<<12)|0x10), #ACK flag    
      'seqno' => $seqno, 
      'ackno' => $ackno
   };

   $pkt = aleSimLib::make_IP_TCP_pkt($params_ref);
   NF::PacketGen::nf_packet_in($queue, $length-$pld_len,
      $delay3+int(rand(2**10)), $batch, $pkt);
   NF::PacketGen::nf_expected_dma_data($queue, 
      $length - $pld_len, $pkt);

}

# *********** Finishing Up - need this in all scripts ! ****************************
my $t = nf_write_sim_files();
print  "--- make_pkts.pl: Generated all configuration packets.\n";
printf "--- make_pkts.pl: Last packet enters system at approx %0d microseconds.\n",($t/1000);
if (nf_write_expected_files()) {
  die "Unable to write expected files\n";
}

nf_create_hardware_file('LITTLE_ENDIAN');
nf_write_hardware_file('LITTLE_ENDIAN');
