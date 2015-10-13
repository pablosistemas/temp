#include <stdio.h>
#include <stdlib.h>
#include <libnet.h>
#include <inttypes.h>
#include <string.h>
#include <time.h>

/* global variables */

static char *from_ip       = "127.0.0.1";
static char *to_ip         = "127.0.0.2";
static uint16_t from_port  = 5555;
static uint16_t to_port    = 6666;
static uint32_t num_pkts   = 1;
static uint8_t ack         = 0;
static char * iface        = "nf2c0";

//struct to nanosleep
struct timespec timing= {(time_t)0,(long)1000};

void print_ip(uint32_t ip)
{
   printf("ip: %d.%d.%d.%d\n",
      ip&0x000000ff,ip>>8&0x0000ff,ip>>16&0x00ff,ip>>24);
   return;
}

void process_args(int argc, char **argv){
   
   char c;

   while((c = getopt(argc, argv,"ahi:p:q:r:s:t:n:")) != -1){
      switch(c) {
         case 'a':
            ack = 1;
            break;
         case 'p':
            from_ip     = optarg;
            break;
         case 'q':
            to_ip       = optarg;
            break;
         case 'r':
            from_port   = atoi(optarg);
            break;
         case 's':
            to_port     = atoi(optarg);
            break;
         case 'n':
            num_pkts    = atoi(optarg);
            break;
         case 't':
            timing.tv_sec = 0;//(time_t)(atoi(optarg)%(int)1E9);
            timing.tv_nsec= (long)atoi(optarg);
            break;
         case 'i':
            iface       = optarg;
            break;
         case 'h':
         default:
            printf("./libnet\n-i <iface>\n-a {if ack}\n-p <from_ip>\n-q <to_ip>\n-r <from_port>\n-s <to_port>\n-t <em ns (default 1000ns)>\n-n <num_pkts>\n");
            exit(1);
      }
   }

   printf("%s:%d -> %s:%d\n",from_ip,from_port,to_ip,to_port);

}

int main(int argc, char **argv)
{
    
    process_args(argc,argv); 

    int c, i, seqn, ackn;
    // context
    libnet_t *l;
    // declarates tags for each header in packet
    libnet_ptag_t tcp, ip, eth;
    // payload, src MAC and dst MAC  
    uint8_t *payload, SA[6], DA[6];
    // payload's length
    uint8_t payload_s = 64;
    // header's fields
    uint32_t src_ip, dst_ip;
   
    // holds error msg if libnet_init() procedure crashs

    char errbuf[LIBNET_ERRBUF_SIZE];
    struct libnet_ether_addr *enet_src;


    payload = malloc(payload_s*sizeof(uint8_t));
    memset(payload,0,payload_s);
    
    // allocates a context for the packet 
    l = libnet_init(LIBNET_LINK, iface, errbuf);
    if(l == NULL){
        printf("libnet_init() error\n");
        goto bad;
    }

    struct in_addr ip_t;
    // src ip
    inet_pton(AF_INET,from_ip,&ip_t);
    src_ip = ip_t.s_addr;
    // dst ip
    inet_pton(AF_INET,to_ip,&ip_t);
    dst_ip = ip_t.s_addr;
 
    // MAC src come from interface 
    enet_src = libnet_get_hwaddr(l);
    sprintf((char*)SA,"%02x:%02x:%02x:%02x:%02x:%02x",
         (uint8_t)enet_src->ether_addr_octet[0],
         (uint8_t)enet_src->ether_addr_octet[1],
         (uint8_t)enet_src->ether_addr_octet[2],
         (uint8_t)enet_src->ether_addr_octet[3],
         (uint8_t)enet_src->ether_addr_octet[4],
         (uint8_t)enet_src->ether_addr_octet[5]);
    
    // dst MAC: MAC of interface of openflow's switch 
    sprintf((char*)DA,"%02x:%02x:%02x:%02x:%02x:%02x",
         0xD0,0x27,0x88,0xBC,0xA8,0xE9);
         
    // the tags are reutilized in each packet we will send
    tcp = ip = eth = LIBNET_PTAG_INITIALIZER;
    
    uint16_t tcp_l = LIBNET_TCP_H+payload_s;
    // send NUM_PKTS packets

    struct timespec req, rem;

    seqn =0;
    ackn =seqn+payload_s+1;
    
    for(i=0;i<num_pkts;i++){
        if(i > 0){
           seqn = ackn;
           ackn = seqn+payload_s+1;
        }
        // builds the tcp header         
        tcp = libnet_build_tcp(
            from_port,to_port,seqn,ackn,
            TH_SYN,32767,0,10,tcp_l,
            payload, payload_s/32, l, tcp);
         
        if(tcp ==-1){
            printf("libnet_build_tcp() error\n");
            goto bad;
        }
        
        // builds the ip header 
        ip = libnet_build_ipv4(
            LIBNET_IPV4_H+LIBNET_TCP_H+payload_s,
            0,242,0,64,IPPROTO_TCP,0,src_ip,dst_ip,
            NULL,0,l,ip);
         
         if(ip==-1){
            printf("libnet_build_ipv4() error\n");
            goto bad;
         }
         
        // builds the ethernet header 
        eth = libnet_build_ethernet(
            DA,SA,ETHERTYPE_IP,NULL,0,l,eth);
        
        if(eth==-1){
            printf("libnet_build_ethernet() error\n");
            goto bad;
         }
        
        // writes context and sends the packet
        c = libnet_write(l);
        
        if(c == -1){
            printf("libnet_write() error\n");
            goto bad;
         }
         else
            printf("Written %d byte TCP packet.\nSeqNum: %d\n",c,seqn);
         
         if(ack){

           req   = timing;
           while(nanosleep(&req, &rem) == -1){
              req.tv_nsec-=rem.tv_nsec;
           }

           tcp = libnet_build_tcp(
               to_port,from_port,seqn,ackn,
               TH_ACK,32767,0,10,tcp_l,
               payload, payload_s/32, l, tcp);
            
           if(tcp ==-1){
               printf("libnet_build_tcp() error\n");
               goto bad;
           }
           
           // builds the ip header 
           ip = libnet_build_ipv4(
               LIBNET_IPV4_H+LIBNET_TCP_H+payload_s,
               0,242,0,64,IPPROTO_TCP,0,dst_ip,src_ip,
               NULL,0,l,ip);
            
            if(ip==-1){
               printf("libnet_build_ipv4() error\n");
               goto bad;
            }
            
           // builds the ethernet header 
           eth = libnet_build_ethernet(
               SA,DA,ETHERTYPE_IP,NULL,0,l,eth);
           
           if(eth==-1){
               printf("libnet_build_ethernet() error\n");
               goto bad;
            }
           
           // writes context and sends the packet
           c = libnet_write(l);
           
           if(c == -1){
               printf("libnet_write() error\n");
               goto bad;
            }
            else
               printf("Written %d byte TCP ACK packet.\nSeqNum: %d\n",c,seqn);
         } 
   }

 
// if things go wrong
bad:
   free(payload);
   libnet_destroy(l);
   exit(EXIT_FAILURE);
}
  
