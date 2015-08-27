#!/bin/env python

from NFTest import *
import libPktTemp

phy2loop0 = ('../connections/conn', [])

nftest_init(sim_loop = [], hw_config = [phy2loop0])
nftest_start()

# packet's header registers 

# MAC DST: "0xD0:0x27:0x88:0xBC:0xA8:0xB9"
nftest_regwrite(reg_defines.MAKER_DST_MAC_LO_REG(),
               0x88<<24|0xBC<<16|0xA8<<8|0xB9)
nftest_regwrite(reg_defines.MAKER_DST_MAC_HI_REG(),
               0x00<<24|0x00<<16|0xD0<<8|0x27)

# MAC SRC: "0xD0:0x27:0x88:0xBC:0xA8:0xB9"
nftest_regwrite(reg_defines.MAKER_SRC_MAC_LO_REG(),
               0x46<<24|0x32<<16|0x43<<8|0x02)
nftest_regwrite(reg_defines.MAKER_SRC_MAC_HI_REG(),
               0x00<<24|0x00<<16|0x00<<8|0x4E)

nftest_regwrite(reg_defines.MAKER_ETHERTYPE_REG(),0x800)

# IP DST: "127.0.0.2"
nftest_regwrite(reg_defines.MAKER_IP_DST_REG(),127<<24|0<<16|0<<8|2)

# IP SRC: "127.0.0.3"
nftest_regwrite(reg_defines.MAKER_IP_SRC_REG(),127<<24|0<<16|0<<8|3)

nftest_regwrite(reg_defines.MAKER_UDP_SRC_PORT_REG(),5555)
nftest_regwrite(reg_defines.MAKER_UDP_DST_PORT_REG(),6666)

output_port = 16

nftest_regwrite(reg_defines.MAKER_OUTPUT_PORT_REG(),output_port)

simReg.regDelay(1000) #1us  

nftest_regread_expect(reg_defines.MAKER_DST_MAC_LO_REG(),
               0x88<<24|0xBC<<16|0xA8<<8|0xB9)
nftest_regread_expect(reg_defines.MAKER_DST_MAC_HI_REG(),
               0x00<<24|0x00<<16|0xD0<<8|0x27)
nftest_regread_expect(reg_defines.MAKER_SRC_MAC_LO_REG(),
               0x46<<24|0x32<<16|0x43<<8|0x02)
nftest_regread_expect(reg_defines.MAKER_SRC_MAC_HI_REG(),
               0x00<<24|0x00<<16|0x00<<8|0x4E)
nftest_regread_expect(reg_defines.MAKER_ETHERTYPE_REG(),0x800)
nftest_regread_expect(reg_defines.MAKER_IP_DST_REG(),
                                 127<<24|0<<16|0<<8|2)
nftest_regread_expect(reg_defines.MAKER_IP_SRC_REG(),
                                 127<<24|0<<16|0<<8|3)
nftest_regread_expect(reg_defines.MAKER_UDP_SRC_PORT_REG(),5555)
nftest_regread_expect(reg_defines.MAKER_UDP_DST_PORT_REG(),6666)
nftest_regread_expect(reg_defines.MAKER_OUTPUT_PORT_REG(),
                              output_port)

simReg.regDelay(1000)

# enable

nftest_regwrite(reg_defines.MAKER_ENABLE_REG(),1)
nftest_regread_expect(reg_defines.MAKER_ENABLE_REG(),1)

##

#The num_pkts set here must be changed in simulacao.v(line 1054), too
NUM_PKTS = 1

eth_hdr =14
ipv4_hdr =20
tcp_hdr =20
pkt_len =64
hdr_len =eth_hdr+ipv4_hdr+tcp_hdr

for iter in range(1):

   for i in range(NUM_PKTS):
      DA = "0xD0:0x27:0x88:0xBC:0xA8:0x%02x"%(i)
      SA = "0x0:0x4E:0x46:0x32:0x43:0x%02x"%(i)
      DST_IP = '192.168.101.%0.3i'%(i)
      SRC_IP = '192.168.101.%0.3i'%(i+1)
      pkt = libPktTemp.make_TCP_pkt(pkt_len=pkt_len, src_MAC=SA, 
            dst_MAC=DA, EtherType=0x800,dst_IP=DST_IP,src_IP=SRC_IP,ttl=64,
            src_PORT = 6666, dst_PORT = 5555 , seq_NUM = i*(pkt_len-hdr_len+1) );
      nftest_send_phy('nf2c0', pkt)

      nftest_expect_dma('nf2c0', pkt)

   nftest_barrier()

   for i in range(NUM_PKTS):
      DA = "0xD0:0x27:0x88:0xBC:0xA8:0x%02x"%(i)
      SA = "0x0:0x4E:0x46:0x32:0x43:0x%02x"%(i)
      DST_IP = '192.168.101.%0.3i'%(i)
      SRC_IP = '192.168.101.%0.3i'%(i+1)
      pkt = libPktTemp.make_TCP_pkt(pkt_len=pkt_len, src_MAC=DA, 
            dst_MAC=SA, EtherType=0x800,dst_IP=SRC_IP,src_IP=DST_IP,ttl=64,
            src_PORT = 5555, dst_PORT = 6666 , seq_NUM = i*(pkt_len-hdr_len+1) );

      # ack 
      pkt[scapy.TCP].flags = 0b10000
      nftest_send_phy('nf2c0', pkt)

      nftest_expect_dma('nf2c0', pkt)

nftest_finish()

'''
   for i in range(20):
      DA = "0xD0:0x27:0x88:0xBC:0xA8:0x%02x"%(i)
      SA = "0x0:0x4E:0x46:0x32:0x43:0x%02x"%(i)
      DST_IP = '192.168.101.%0.3i'%(i)
      SRC_IP = '192.168.101.%0.3i'%(i+1)
      pkt = libPktTemp.make_UDP_pkt(pkt_len=pkt_len, src_MAC=DA, dst_MAC=SA, EtherType=0x800,dst_IP=SRC_IP, 
            src_IP=DST_IP, ttl=64, src_PORT = 5555, dst_PORT = 6666);

      nftest_send_phy('nf2c0', pkt)

      nftest_expect_dma('nf2c0', pkt)

   nftest_barrier()
   
   simPkt.delay(1000);

'''
