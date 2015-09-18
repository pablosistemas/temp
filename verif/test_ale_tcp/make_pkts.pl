#!/usr/bin/perl -w
# make_pkts.pl

use NF::PacketGen;
use NF::PacketLib;
use NF::RegAccess;
use SimLib;

use reg_defines_temp;

$delay = '@4us';
$batch = 0;
my $iface = 'nf2c0';

nf_set_environment( { PORT_MODE => 'PHYSICAL', MAX_PORTS => 4 } );

# use strict AFTER the $delay, $batch and %reg are declared
use strict;
use vars qw($delay $batch %reg);

# Prepare the DMA and enable interrupts
prepare_DMA('@3.9us');
enable_interrupts(0);

NF::PacketGen::nf_PCI_write32(0,$batch,MAKER_DST_MAC_HI_REG(),0x00<<24|0x00<<16|0xD0<<8|0x27);
NF::PacketGen::nf_PCI_write32(0,$batch,MAKER_DST_MAC_LO_REG(),0x88<<24|0xBC<<16|0xA8<<8|0xB9);
NF::PacketGen::nf_PCI_write32(0,$batch,MAKER_SRC_MAC_HI_REG(),0x00<<24|0x00<<16|0x00<<8|0x4E);
NF::PacketGen::nf_PCI_write32(0,$batch,MAKER_SRC_MAC_LO_REG(),0x46<<24|0x32<<16|0x43<<8|0x02);

NF::PacketGen::nf_PCI_write32(0,$batch,MAKER_ETHERTYPE_REG(),0x800);
NF::PacketGen::nf_PCI_write32(0,$batch,MAKER_IP_DST_REG(),127<<24|1);
NF::PacketGen::nf_PCI_write32(0,$batch,MAKER_IP_SRC_REG(),127<<24|2);

NF::PacketGen::nf_PCI_write32(0,$batch,MAKER_UDP_SRC_PORT_REG(),5556);
NF::PacketGen::nf_PCI_write32(0,$batch,MAKER_UDP_DST_PORT_REG(),6665);

NF::PacketGen::nf_PCI_write32(0,$batch,MAKER_OUTPUT_PORT_REG(),4);
NF::PacketGen::nf_PCI_write32('@0.1us',$batch,MAKER_ENABLE_REG(),1);

# NetFPGA OUTPUT PORTS: ONE_HOT
# 1, 2, 4, 8, 16, 32, 64, 128

my $SRC_IP;
my $DST_IP;
my $SA;
my $DA;

my $length = 100;
my $ttl = 30;
my $dst_ip = 0;
my $src_ip = 0;
my $seqno = 0;
my $ackno = 0;

my $pkt;
my $cpudelay = 25000;
my $queue;

$delay = 9000;
$queue = 1;

$length = 64;

my $num_pkts = 15;
my $num_iter = 1;

$seqno = int(rand(2**32));

my $eth_len = 14;
my $ip_total_len = $length-$eth_len;
my $ip_hdr_len = 20;
my $data_offset = 5; #number of 32-bit words in tcp hdr
my $tcp_hdr_len = $data_offset*4;
my $pld_len = $ip_total_len-$ip_hdr_len-$tcp_hdr_len;

for(my $j = 0; $j < $num_iter; $j++){

   $ackno = $seqno+$pld_len+1;

   for(my $i = 0; $i < $num_pkts; $i++){
      # cria pacote TCP -> função adicionada na biblioteca
      
      $SRC_IP = sprintf("192.168.%d.1",$i);
      $DST_IP = sprintf("192.168.%d.1",$i+1);

      $SA = sprintf("00:ca:fe:00:00:%02d",$i);
      $DA = sprintf("00:ca:fe:00:00:%02d",$i+1);
      

      my $params_ref = [$length,
         $SA,
         $DA,
         $ttl, 
         $SRC_IP,
         $DST_IP,
         6000+$i,
         6000+$i+1,
         0x02, # offset|SYN flag     
         $seqno, 0 
      ];

      $pkt = SimLib::make_IP_TCP_pkt(@{$params_ref});

      NF::PacketGen::nf_packet_in($queue, $length, 
         $delay, $batch, $pkt);
      NF::PacketGen::nf_expected_dma_data($queue, 
         $length, $pkt);

      # ACK

      my $params_ref = [$length,
         $DA,
         $SA,
         $ttl, 
         $DST_IP,
         $SRC_IP,
         6000+$i+1,
         6000+$i,
         0x10, # ACK flag      
         0, $ackno
      ];

      $pkt = SimLib::make_IP_TCP_pkt(@{$params_ref});
      NF::PacketGen::nf_packet_in($queue, $length, 
         $delay+int(rand(2**10)), $batch, $pkt);
      NF::PacketGen::nf_expected_dma_data($queue, 
         $length, $pkt);
   }

   $seqno = $seqno+$j*$pld_len+1;

}

NF::PacketGen::nf_expected_dma_data(3,$length,$pkt);

nf_PCI_read32('@30us',$batch,IN_ARB_NUM_PKTS_SENT_REG(),
   $num_pkts);

nf_PCI_read32('@9us',$batch,
   MAC_GRP_0_TX_QUEUE_NUM_PKTS_SENT_REG (),$num_pkts/4);

nf_PCI_read32('@9us',$batch,
   MAC_GRP_1_TX_QUEUE_NUM_PKTS_SENT_REG (),$num_pkts/4);

nf_PCI_read32('@9us',$batch,
   MAC_GRP_2_TX_QUEUE_NUM_PKTS_SENT_REG (),$num_pkts/4);

nf_PCI_read32('@9us',$batch,
   MAC_GRP_3_TX_QUEUE_NUM_PKTS_SENT_REG (),$num_pkts/4);

nf_PCI_read32('@9us',$batch,
   MAC_GRP_0_RX_QUEUE_NUM_PKTS_DEQUEUED_REG (),$num_pkts/4);

nf_PCI_read32('@9us',$batch,
   MAC_GRP_1_RX_QUEUE_NUM_PKTS_DEQUEUED_REG (),$num_pkts/4);

nf_PCI_read32('@9us',$batch,
   MAC_GRP_2_RX_QUEUE_NUM_PKTS_DEQUEUED_REG (),$num_pkts/4);

nf_PCI_read32('@9us',$batch,
   MAC_GRP_3_RX_QUEUE_NUM_PKTS_DEQUEUED_REG (),$num_pkts/4);

nf_PCI_read32('@9us',$batch,
   CPU_QUEUE_0_TX_QUEUE_NUM_PKTS_ENQUEUED_REG (),$num_pkts/4);

nf_PCI_read32('@9us',$batch,
   CPU_QUEUE_1_TX_QUEUE_NUM_PKTS_ENQUEUED_REG (),$num_pkts/4);

nf_PCI_read32('@9us',$batch,
   CPU_QUEUE_2_TX_QUEUE_NUM_PKTS_ENQUEUED_REG (),$num_pkts/4);

nf_PCI_read32('@9us',$batch,
   CPU_QUEUE_3_TX_QUEUE_NUM_PKTS_ENQUEUED_REG (),$num_pkts/4);


nf_PCI_read32('@9us',$batch,
   CPU_QUEUE_0_RX_QUEUE_NUM_PKTS_ENQUEUED_REG (),$num_pkts/4);

nf_PCI_read32('@9us',$batch,
   CPU_QUEUE_1_RX_QUEUE_NUM_PKTS_ENQUEUED_REG (),$num_pkts/4);

nf_PCI_read32('@9us',$batch,
   CPU_QUEUE_2_RX_QUEUE_NUM_PKTS_ENQUEUED_REG (),$num_pkts/4);

nf_PCI_read32('@9us',$batch,
   CPU_QUEUE_3_RX_QUEUE_NUM_PKTS_ENQUEUED_REG (),$num_pkts/4);



# *********** Finishing Up - need this in all scripts ! ****************************
my $t = nf_write_sim_files();
print  "--- make_pkts.pl: Generated all configuration packets.\n";
printf "--- make_pkts.pl: Last packet enters system at approx %0d microseconds.\n",($t/1000);
if (nf_write_expected_files()) {
  die "Unable to write expected files\n";
}

nf_create_hardware_file('LITTLE_ENDIAN');
nf_write_hardware_file('LITTLE_ENDIAN');
