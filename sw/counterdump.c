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
char ip[INET_ADDRSTRLEN];
uint16_t porta;

/* Function declarations */
void *dumpCounts();
void processArgs (int , char **);
void usage (void);

int main(int argc, char *argv[])
{
  nf2.device_name = DEFAULT_IFACE;

  /* Default */
  sprintf(ip,"127.0.0.1");
  porta = 7777;

  processArgs(argc, argv);

  // Open the interface if possible
  if (check_iface(&nf2))
    {
      exit(1);
    }
  if (openDescriptor(&nf2))
    {
      exit(1);
    }

  /* SOCKET */
  int fd;
  if((fd = socket(AF_INET,SOCK_DGRAM,0)) < 0){
     printf("ERROR! socket\n");
     goto exit_thread;
  }

  /* THREAD - dumpCount() */
  int rc;
  pthread_t thread;       
  rc = pthread_create(&thread,NULL,dumpCounts,NULL);
  if(rc){
     printf("ERROR! Return code from pthread_create is %d\n", rc);
     goto exit_no_thread;
  }
  
  struct sockaddr_in servidor; 
  bzero((void*)&servidor, sizeof(servidor));
  servidor.sin_family = AF_INET;
  inet_pton(AF_INET,ip,(void*)&(servidor.sin_addr.s_addr));
  servidor.sin_port = htons(porta);

  int rb;
  if((rb = bind(fd, (struct sockaddr *)&servidor, sizeof(servidor))) < 0){
    printf("ERROR! bind\n");
    goto exit_thread;
  } 

  printf("listener: waiting to recvfrom\n");

  char buf[MAXBUFLEN];
  int numbytes;
  struct sockaddr_storage their_addr;
  socklen_t addr_len;
   
  while(1){
     if((numbytes = recvfrom(fd, buf, MAXBUFLEN-1, 0,
              (struct sockaddr *)&their_addr, &addr_len)) == -1){
        printf("ERROR! recvfrom\n");
        goto exit_thread;
     }
      
     buf[numbytes] = '\0';
     printf("DADOS DO PACOTE: \n%s\n\n",buf); 
  }

exit_thread:
  pthread_exit(NULL);

exit_no_thread: 
  closeDescriptor(&nf2);
  close(fd); 
  return 0;
}

void *dumpCounts()
{
  unsigned val;

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

  pthread_exit(NULL);
}

/*
 *  Process the arguments.
 */
void processArgs (int argc, char **argv )
{
  char c;

  /* don't want getopt to moan - I can do that just fine thanks! */
  opterr = 0;

  while ((c = getopt (argc, argv, "i:h")) != -1)
    {
      switch (c)
	{
	case 'i':	/* interface name */
	  nf2.device_name = optarg;
	  break;
	case '?':
	  if (isprint (optopt))
	    fprintf (stderr, "Unknown option `-%c'.\n", optopt);
	  else
	    fprintf (stderr,
		     "Unknown option character `\\x%x'.\n",
		     optopt);
	case 'h':
   
   case 'a': 
      sprintf(ip,"%s",optarg);
      break;

   case 'p': 
      porta = (uint16_t)atoi(optarg);
      break;

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
  printf("         -h : Print this message and exit.\n");
}
