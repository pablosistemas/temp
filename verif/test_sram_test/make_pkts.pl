#!/usr/local/bin/perl -w
# make_pkts.pl

use NF::Base "projects/reference_router/lib/Perl5";
use NF::PacketGen;
use NF::PacketLib;
use NF::RegAccess;
use SimLib;
use RouterLib;

use reg_defines_firewall;

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
   NF::PacketGen::nf_PCI_write32($delay,0,SRAM_BASE_ADDR()+($_<<2),0);
}

foreach (0..$max){
   NF::PacketGen::nf_PCI_read32($delay,0,SRAM_BASE_ADDR()+($_<<2),0);
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
