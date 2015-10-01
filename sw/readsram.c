/* ****************************************************************************
 * vim:set shiftwidth=2 softtabstop=2 expandtab:
 * $Id: counterdump.c 5455 2009-05-05 18:18:16Z g9coving $
 *
 * Module:  rsram.c
 * Project: NetFPGA NIC
 * Description: dumps the sram to stdout
 * Author: 
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
uint32_t enderecos;
static struct nf2device nf2;
static uint8_t reading = 0;

/* Function declarations */
void dumpCounts();
void processArgs (int , char **);
void usage (void);

int main(int argc, char *argv[]){

   nf2.device_name = DEFAULT_IFACE;

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
  int i;

  for(i=0;i<enderecos;i++)
     writeReg(&nf2, SRAM_BASE_ADDR+(i<<2), 0);

  if(reading)
     for(i=0;i<enderecos;i++){
        readReg(&nf2, SRAM_BASE_ADDR+(i<<2), &val);
        printf("SRAM[%06d]: %u\n", i,val);
     }
}

/*
 *  Process the arguments.
 */
void processArgs (int argc, char **argv )
{
   char c;

   /* don't want getopt to moan - I can do that just fine thanks! */
   opterr = 0;

   while ((c = getopt (argc, argv, ":i:n:hr")) != -1){
      switch (c){
         case 'n':
            enderecos = atoi(optarg);
            break;

         case 'i':	/* interface name */
           nf2.device_name = optarg;
           break;
      
         case 'r':
            reading = 1;
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
  printf("Usage: ./readsram <options> \n\n");
  printf("Options: -a <ip address> : endereco ip. Default: 127.0.0.1\n");
  printf("Options: -p <porta UDP> : porta. Default: 7777.\n");
  printf("Options: -i <iface> : interface name (default nf2c0)\n");
  printf("         -h : Print this message and exit.\n");
}
