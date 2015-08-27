#!/usr/bin/perl -w

use NF::Base "projects/reference_router/lib/Perl5";
use NF::PacketGen;
use NF::PacketLib;
use SimLib;
use RouterLib;

use reg_defines_firewall;

$delay = '@4us';
$batch = 0;

nf_set_environment({ PORT_MODE => 'PHYSICAL', MAX_PORTS => 1});

use strict;
use vars qw($delay $batch %reg);

my @pdrop = (1210, 80, 22, 667);

NF::PacketGen::nf_PCI_write32($delay,$batch,FIREWALL_DPORT1_REG(),$pdrop[0]);

NF::PacketGen::nf_PCI_write32($delay,$batch,FIREWALL_DPORT1_REG(),$pdrop[1]);

NF::PacketGen::nf_PCI_write32($delay,$batch,FIREWALL_DPORT1_REG(),$pdrop[2]);

NF::PacketGen::nf_PCI_write32($delay,$batch,FIREWALL_DPORT1_REG(),$pdrop[3]);

NF::PacketGen::nf_PCI_read32($delay,$batch,FIREWALL_DPORT1_REG(),$pdrop[0]);

NF::PacketGen::nf_PCI_read32($delay,$batch,FIREWALL_DPORT1_REG(),$pdrop[1]);

NF::PacketGen::nf_PCI_read32($delay,$batch,FIREWALL_DPORT1_REG(),$pdrop[2]);

NF::PacketGen::nf_PCI_read32($delay,$batch,FIREWALL_DPORT1_REG(),$pdrop[3]);

my $treg = NF::PacketGen::nf_pci_sim_files();
print "Ultimo acesso pela interface de registradores: $treg"

########Check SRAM########

$delay = '@1us';
NF::PacketGen::nf_PCI_read32($delay,$batch,SRAM_BASE_ADDR(),$pdrop[2]<<16|$pdrop[3]);

NF::PacketGen::nf_PCI_read32($delay,$batch,SRAM_BASE_ADDR()+4,$pdrop[0]<<16|$pdrop[1]);

########Pacotes########
# ports: 1,2,3 and 4

my $ROUTER_PORT_1_MAC = '00:ca:fe:00:00:01';
my $ROUTER_PORT_2_MAC = '00:ca:fe:00:00:02';
my $ROUTER_PORT_3_MAC = '00:ca:fe:00:00:03';
my $ROUTER_PORT_4_MAC = '00:ca:fe:00:00:04';

my $ROUTER_PORT_1_IP = '192.168.1.1';
my $ROUTER_PORT_2_IP = '192.168.2.1';
my $ROUTER_PORT_3_IP = '192.168.3.1';
my $ROUTER_PORT_4_IP = '192.168.4.1';

my $DEST_IP_1 = '192.168.1.5';
my $DEST_IP_2 = '192.168.2.5';
my $DEST_IP_3 = '192.168.3.5';
my $DEST_IP_4 = '192.168.4.5';
my $DEST_IP_4a = '192.168.4.128';
my $DEST_IP_4b = '192.168.4.129';

my $NEXT_IP_1 = '192.168.1.2';
my $NEXT_IP_2 = '192.168.2.2';
my $NEXT_IP_3 = '192.168.3.2';
my $NEXT_IP_4 = '192.168.4.2';

my $next_hop_1_DA = '00:fe:ed:01:d0:65';
my $next_hop_2_DA = '00:fe:ed:02:d0:65';
my $next_hop_3_DA = '00:fe:ed:03:d0:65';
my $next_hop_4_DA = '00:fe:ed:04:d0:65';

my $length = 100;
my $TTL = 30;
my $DA = ;
my $SA = $ROUTER_PORT_1_MAC;
my $dst_ip = 0;
my $src_ip = 0;
my $pkt;
my $in_port;
my $out_port;
$delay = '@1us';

my $NUM_PACKETS = 4;
my $i = 0;
while ($i < NUM_PACKETS){
   
}

$pkt = NF::SimLib::make_IP_pkt($length,$DA,$SA,$TTL,$dst_ip,$src_ip);

NF::PacketGen::nf_packet_in(1,$sizeofpkt,$delay,$batch,pkt);

if(nf_write_expected_files()){
   die "Erro na escrita dos arquivos esperados\n"
}

nf_create_hardware_file("LITTLE_ENDIAN");
nf_write_hardware_file("LITTLE_ENDIAN");
