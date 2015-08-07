#!/bin/env python

from NFTest import *
import sys
sys.path.append('/root/netfpga/projects/temp/lib/Python')

import libPktTemp

phy2loop0 = ('../connections/conn', [])

nftest_init(sim_loop = [], hw_config = [phy2loop0])
nftest_start()

#The num_pkts set here must be changed in simulacao.v(line 1054), too
NUM_PKTS = 10

eth_hdr=14
ipv4_hdr=20
icmp_hdr=4

for iter in range(1):
   for i in range(NUM_PKTS):
      DA = "0xD0:0x27:0x88:0xBC:0xA8:0x%02x"%(i)
      SA = "0x0:0x4E:0x46:0x32:0x43:0x%02x"%(i)
      DST_IP = '192.168.101.%0.3i'%(i)
      SRC_IP = '192.168.101.%0.3i'%(i+1)
      pkt = make_ICMP_host_unreach_pkt(src_MAC=DA, dst_MAC=SA, EtherType=0x800,dst_IP=DST_IP, 
            src_IP=SRC_IP, ttl=64);

      nftest_send_phy('nf2c0', pkt)

      nftest_expect_dma('nf2c0', pkt)

nftest_barrier()

nftest_finish()
