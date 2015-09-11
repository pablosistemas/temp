/* ****************************************************************************
 * vim:set shiftwidth=2 softtabstop=2 expandtab:
 * $Id: counterdump.c 5455 2009-05-05 18:18:16Z g9coving $
 *
 * Module:  counterdump.c
 * Project: NetFPGA NIC
 * Description: dumps the MAC Rx/Tx counters to stdout
 * Author: Jad Naous
 *
 * Change history:
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include <net/if.h>

#include "../lib/C/reg_defines_temp.h"
#include "../../../lib/C/common/nf2.h"
#include "../../../lib/C/common/nf2util.h"

#include <pthread.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <inttypes.h>
#include <arpa/inet.h>
#include <strings.h>

#include <ctype.h>

#define PATHLEN		80

#define DEFAULT_IFACE	"nf2c0"

#define MAXBUFLEN 100

/* Global vars */
static struct nf2device nf2;
uint16_t porta;

// MAC DMA port
uint32_t out_port = 0x4;

// ip addr
struct in_addr src_addr, dst_addr;

/* Function declarations */
void dumpCounts();
void processArgs (int , char **);
void usage (void);

int main(int argc, char *argv[]){

   nf2.device_name = DEFAULT_IFACE;

   /* Default */
   inet_pton(AF_INET,"127.0.0.1",&src_addr);
   inet_pton(AF_INET,"127.0.0.2",&dst_addr);
   porta = 7777;

   processArgs(argc, argv);

   // Open the interface if possible
   if (check_iface(&nf2))
      exit(1);

   if (openDescriptor(&nf2))
      exit(1);

   dumpCounts();
  
   closeDescriptor(&nf2);
   return 0;
}

uint32_t big2little_endian(uint32_t addr){
   uint32_t temp = 0;
   int i;
   for(i=0;i<4;i++){
      temp = temp | (addr>>(i*8) & 0xff)<<((3-i)*8);
   }
   return temp;
}

void dumpCounts()
{
  unsigned val;

  /* udp header */
  writeReg(&nf2,MAKER_DST_MAC_HI_REG,0x00<<24|0x00<<16|0xC8<<8|0x2A);
  writeReg(&nf2,MAKER_DST_MAC_LO_REG,0x14<<24|0x39<<16|0x71<<8|0xCD);

  writeReg(&nf2,MAKER_SRC_MAC_HI_REG,0x00<<24|0x00<<16|0xD0<<8|0x27);
  writeReg(&nf2,MAKER_SRC_MAC_LO_REG,0x88<<24|0xBC<<16|0xA8<<8|0xB9);

  writeReg(&nf2,MAKER_ETHERTYPE_REG,0x800);

  uint32_t addr = big2little_endian(src_addr.s_addr);

  writeReg(&nf2,MAKER_IP_DST_REG,addr);

  addr = big2little_endian(dst_addr.s_addr);

  writeReg(&nf2,MAKER_IP_SRC_REG,addr);

  writeReg(&nf2,MAKER_UDP_SRC_PORT_REG,porta);
  writeReg(&nf2,MAKER_UDP_DST_PORT_REG,porta);

  writeReg(&nf2,MAKER_OUTPUT_PORT_REG,out_port);
  readReg(&nf2,MAKER_OUTPUT_PORT_REG,&val);
  printf("output port: %d\n",val); 

  /* enable packets */
  writeReg(&nf2,MAKER_ENABLE_REG,1);

   /* MAC QUEUES */
  readReg(&nf2, MAC_GRP_0_RX_QUEUE_NUM_PKTS_STORED_REG, &val);
  printf("Num pkts received on port 0:           %u\n", val);
  readReg(&nf2, MAC_GRP_0_RX_QUEUE_NUM_PKTS_DROPPED_FULL_REG, &val);
  printf("Num pkts dropped (rx queue 0 full):    %u\n", val);
  readReg(&nf2, MAC_GRP_0_RX_QUEUE_NUM_PKTS_DROPPED_BAD_REG, &val);
  printf("Num pkts dropped (bad fcs q 0):        %u\n", val);
  readReg(&nf2, MAC_GRP_0_RX_QUEUE_NUM_BYTES_PUSHED_REG, &val);
  printf("Num bytes received on port 0:          %u\n", val);
  readReg(&nf2, MAC_GRP_0_TX_QUEUE_NUM_PKTS_SENT_REG, &val);
  printf("Num pkts sent from port 0:             %u\n", val);
  readReg(&nf2, MAC_GRP_0_TX_QUEUE_NUM_BYTES_PUSHED_REG, &val);
  printf("Num bytes sent from port 0:            %u\n\n", val);

  readReg(&nf2, MAC_GRP_1_RX_QUEUE_NUM_PKTS_STORED_REG, &val);
  printf("Num pkts received on port 1:           %u\n", val);
  readReg(&nf2, MAC_GRP_1_RX_QUEUE_NUM_PKTS_DROPPED_FULL_REG, &val);
  printf("Num pkts dropped (rx queue 1 full):    %u\n", val);
  readReg(&nf2, MAC_GRP_1_RX_QUEUE_NUM_PKTS_DROPPED_BAD_REG, &val);
  printf("Num pkts dropped (bad fcs q 1):        %u\n", val);
  readReg(&nf2, MAC_GRP_1_RX_QUEUE_NUM_BYTES_PUSHED_REG, &val);
  printf("Num bytes received on port 1:          %u\n", val);
  readReg(&nf2, MAC_GRP_1_TX_QUEUE_NUM_PKTS_SENT_REG, &val);
  printf("Num pkts sent from port 1:             %u\n", val);
  readReg(&nf2, MAC_GRP_1_TX_QUEUE_NUM_BYTES_PUSHED_REG, &val);
  printf("Num bytes sent from port 1:            %u\n\n", val);

  readReg(&nf2, MAC_GRP_2_RX_QUEUE_NUM_PKTS_STORED_REG, &val);
  printf("Num pkts received on port 2:           %u\n", val);
  readReg(&nf2, MAC_GRP_2_RX_QUEUE_NUM_PKTS_DROPPED_FULL_REG, &val);
  printf("Num pkts dropped (rx queue 2 full):    %u\n", val);
  readReg(&nf2, MAC_GRP_2_RX_QUEUE_NUM_PKTS_DROPPED_BAD_REG, &val);
  printf("Num pkts dropped (bad fcs q 2):        %u\n", val);
  readReg(&nf2, MAC_GRP_2_RX_QUEUE_NUM_BYTES_PUSHED_REG, &val);
  printf("Num bytes received on port 2:          %u\n", val);
  readReg(&nf2, MAC_GRP_2_TX_QUEUE_NUM_PKTS_SENT_REG, &val);
  printf("Num pkts sent from port 2:             %u\n", val);
  readReg(&nf2, MAC_GRP_2_TX_QUEUE_NUM_BYTES_PUSHED_REG, &val);
  printf("Num bytes sent from port 2:            %u\n\n", val);

  readReg(&nf2, MAC_GRP_3_RX_QUEUE_NUM_PKTS_STORED_REG, &val);
  printf("Num pkts received on port 3:           %u\n", val);
  readReg(&nf2, MAC_GRP_3_RX_QUEUE_NUM_PKTS_DROPPED_FULL_REG, &val);
  printf("Num pkts dropped (rx queue 3 full):    %u\n", val);
  readReg(&nf2, MAC_GRP_3_RX_QUEUE_NUM_PKTS_DROPPED_BAD_REG, &val);
  printf("Num pkts dropped (bad fcs q 3):        %u\n", val);
  readReg(&nf2, MAC_GRP_3_RX_QUEUE_NUM_BYTES_PUSHED_REG, &val);
  printf("Num bytes received on port 3:          %u\n", val);
  readReg(&nf2, MAC_GRP_3_TX_QUEUE_NUM_PKTS_SENT_REG, &val);
  printf("Num pkts sent from port 3:             %u\n", val);
  readReg(&nf2, MAC_GRP_3_TX_QUEUE_NUM_BYTES_PUSHED_REG, &val);
  printf("Num bytes sent from port 3:            %u\n\n", val);

  /* CPU QUEUES */
  readReg(&nf2, CPU_QUEUE_0_RX_QUEUE_NUM_PKTS_IN_QUEUE_REG, &val);
  printf("Num pkts in queue on cpu 0:           %u\n", val);
  readReg(&nf2, CPU_QUEUE_0_RX_QUEUE_NUM_PKTS_ENQUEUED_REG, &val);
  printf("Num pkts enqueued on cpu 0:           %u\n", val);
  readReg(&nf2, CPU_QUEUE_0_RX_QUEUE_NUM_PKTS_DEQUEUED_REG, &val);
  printf("Num pkts dequeued on cpu 0:           %u\n", val);

  readReg(&nf2, CPU_QUEUE_1_RX_QUEUE_NUM_PKTS_IN_QUEUE_REG, &val);
  printf("Num pkts in queue on cpu 1:           %u\n", val);
  readReg(&nf2, CPU_QUEUE_1_RX_QUEUE_NUM_PKTS_ENQUEUED_REG, &val);
  printf("Num pkts enqueued on cpu 1:           %u\n", val);
  readReg(&nf2, CPU_QUEUE_1_RX_QUEUE_NUM_PKTS_DEQUEUED_REG, &val);
  printf("Num pkts dequeued on cpu 1:           %u\n", val);

  readReg(&nf2, CPU_QUEUE_2_RX_QUEUE_NUM_PKTS_IN_QUEUE_REG, &val);
  printf("Num pkts in queue on cpu 2:           %u\n", val);
  readReg(&nf2, CPU_QUEUE_2_RX_QUEUE_NUM_PKTS_ENQUEUED_REG, &val);
  printf("Num pkts enqueued on cpu 2:           %u\n", val);
  readReg(&nf2, CPU_QUEUE_2_RX_QUEUE_NUM_PKTS_DEQUEUED_REG, &val);
  printf("Num pkts dequeued on cpu 2:           %u\n", val);

  readReg(&nf2, CPU_QUEUE_3_RX_QUEUE_NUM_PKTS_IN_QUEUE_REG, &val);
  printf("Num pkts in queue on cpu 3:           %u\n", val);
  readReg(&nf2, CPU_QUEUE_3_RX_QUEUE_NUM_PKTS_ENQUEUED_REG, &val);
  printf("Num pkts enqueued on cpu 3:           %u\n", val);
  readReg(&nf2, CPU_QUEUE_3_RX_QUEUE_NUM_PKTS_DEQUEUED_REG, &val);
  printf("Num pkts dequeued on cpu 3:           %u\n", val);


  readReg(&nf2, MAKER_NUM_EVT_PKTS_SENT_REG, &val);
  printf("Num pkts with bloom filter data:           %u\n", val);
}

/*
 *  Process the arguments.
 */
void processArgs (int argc, char **argv )
{
   char c;
   uint32_t op;

   /* don't want getopt to moan - I can do that just fine thanks! */
   opterr = 0;

   while ((c = getopt (argc, argv, "a:b:i:o:h")) != -1){
      switch (c){
         case 'a':  //ip addr
            inet_pton(AF_INET,optarg,&src_addr);
            break;

         case 'b':
            inet_pton(AF_INET,optarg,&dst_addr);
            break;

         case 'i':	/* interface name */
           nf2.device_name = optarg;
           break;

         case 'p': 
            porta = (uint16_t)atoi(optarg);
            break;

         case 'o':
            op = atoi(optarg);
            //out_port = 1<<(2*op);
            out_port = op;
            break;

         case '?':
           if (isprint (optopt))
             fprintf (stderr, "Unknown option `-%c'.\n", optopt);
           else
             fprintf (stderr,
                 "Unknown option character `\\x%x'.\n",
                 optopt);
         
         case 'h':

         default:
           usage();
           exit(1);
      }
   }
}


/*
 *  Describe usage of this program.
 */
void usage (void)
{
  printf("Usage: ./counterdump <options> \n\n");
  printf("Options: -a <ip address> : endereco ip. Default: 127.0.0.1.\n");
  printf("Options: -p <porta UDP> : porta. Default: 7777.\n");
  printf("Options: -i <iface> : interface name (default nf2c0)\n");
  printf("Options: -o <nf2cX> : interface number (default 0)\n");
  printf("         -h : Print this message and exit.\n");
}
