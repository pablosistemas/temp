/* Open a device whose name from argv and call pcap_next to read just
 * one packet.
 * */

#include <stdio.h>
#include <stdlib.h>
#include <pcap/pcap.h>
#include <errno.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#include <netinet/if_ether.h>

// prototypes
uint16_t handle_ethernet (u_char*,const struct pcap_pkthdr*,const u_char*);
uint16_t handle_IP (u_char*,const struct pcap_pkthdr*,const u_char*);
uint16_t handle_UDP (u_char*,const struct pcap_pkthdr*,const u_char*);
//uint16_t handle_TCP (u_char*,const struct pcap_pkthdr*,const u_char*);
void handle_PLD (u_char*,const struct pcap_pkthdr*,const u_char*);

struct my_ip {
   uint8_t        ip_vhl;
#define IP_V(ip)  (((ip)->ip_vhl&0xf0) >> 4)   
#define IP_HL(ip) ((ip)->ip_vhl&0x0f)
   uint8_t        ip_tos;
   uint16_t       ip_len;
   uint16_t       ip_id;
   uint16_t       ip_off;
#define IP_DF 0x4000
#define IP_MF 0x2000
#define IP_OFFMASK 0x1fff
   uint8_t        ip_ttl;
   uint8_t        ip_p;
   u_short        ip_sum;
   struct in_addr ip_src, ip_dst;   
};

struct my_udp {
   uint16_t p_src;
   uint16_t p_dst;
   uint16_t len;
   uint16_t chk;
};

struct my_pld_data {
   uint32_t ip_src;
   uint32_t ip_dst;
   uint16_t p_src;
   uint16_t p_dst;
   uint32_t medicao;
};

void my_callback(u_char *args,const struct pcap_pkthdr *hdr, const u_char *packet){
   uint16_t type = handle_ethernet(args,hdr,packet);
   uint16_t ipproto = -1;
   uint16_t pld_l =0;

   printf("type eth: %d\n",type);

   if(type == ETHERTYPE_IP){
      ipproto = handle_IP(args,hdr,packet);
   } else if (type == ETHERTYPE_ARP) {
      printf("ARP\n");
   }
   if(ipproto == 17)
      pld_l = handle_UDP(args,hdr,packet);
   else if(ipproto == 6){
      //pld_l = handle_TCP(args,hdr,packet);
   }
   printf("length pld: %d\n",pld_l);
   if(pld_l > 0)
      handle_PLD(args,hdr,packet);

}

uint16_t handle_ethernet (u_char *args,
      const struct pcap_pkthdr *pkthdr,
      const u_char* packet){
   struct ether_header *eptr;
   eptr = (struct ether_header *)packet;

   if(ntohs(eptr->ether_type) == ETHERTYPE_IP){
      printf("Ethernet type hex: %x dec %d is an IP packet\n",ntohs(eptr->ether_type),ntohs(eptr->ether_type));

   } else if (ntohs(eptr->ether_type) == ETHERTYPE_ARP) {
      printf("Ethernet type hex: %x dec %d is ARP packet\n",ntohs(eptr->ether_type), ntohs(eptr->ether_type));
   } else {
      printf("Ethernet type %x not IP", ntohs(eptr->ether_type));
      exit(-1);
   }

   return ntohs(eptr->ether_type);
}

void handle_PLD (u_char *args,const struct pcap_pkthdr* hdr,
      const u_char *packet){

   uint32_t length =hdr->len;
   
   length-=sizeof(struct ether_header);
   length-=sizeof(struct my_ip);
   length-=sizeof(struct my_udp);

   // if UDP hdr is smaller than the normal
   if(length < 0){
      printf("PAYLOAD error %d",length);
      return;
   }

   if(length %2 != 0){
      printf("ERROR: payload length must be even number\n");
   }

   struct my_pld_data *data_ptr;
   char ip[INET_ADDRSTRLEN];

   int i;

   printf("*********************************\n");
   data_ptr = (struct my_pld_data *)(packet+sizeof(struct ether_header)+
         sizeof(struct my_ip)+sizeof(struct my_udp)+6*sizeof(uint8_t));
   for(i = 0;i < length-1; i += sizeof(struct my_pld_data)){

      // ip src
      inet_ntop(AF_INET,&data_ptr->ip_src,ip,INET_ADDRSTRLEN);     
      printf("IP SRC: %s, ",ip);

      // ip dst
      inet_ntop(AF_INET,&data_ptr->ip_dst,ip,INET_ADDRSTRLEN);     
      printf("IP DST: %s, ",ip);

      printf("P SRC: %d, ",data_ptr->p_src);//ntohs(*p_ptr));
      printf("P DST: %d, ",data_ptr->p_dst);//ntohs(*(p_ptr+1)));
      printf("MEDICAO: %d, ",ntohl(data_ptr->medicao));//(uint32_t)(*(p_ptr+2)));
      printf("\n---------------------------------\n");

      data_ptr++;
   }
   printf("\n\n");
}


uint16_t handle_UDP (u_char *args,const struct pcap_pkthdr* hdr,
      const u_char *packet){
   const struct my_udp *udp;
   uint32_t length =hdr->len;
   
   int len;

   udp =(struct my_udp*)(packet+sizeof(struct ether_header)+sizeof(struct my_ip));
   length-=sizeof(struct ether_header);
   length-=sizeof(struct my_ip);

   // if UDP hdr is smaller than the normal
   if(length < sizeof(struct my_udp)){
      printf("truncated udp %d",length);
      return -1;
   }

   len =ntohs(udp->len);

   if(length < len)
      printf("\ntruncated UDP - %d bytes missing\n", len-length);
   
   printf("UDP: ");
   printf("%d ",ntohs(udp->p_src));
   printf("%d %d\n",ntohs(udp->p_dst),len);
   
   return (len-8); //pld length
}

uint16_t handle_IP (u_char *args,const struct pcap_pkthdr* hdr,
      const u_char *packet){
   const struct my_ip *ip;
   u_int length =hdr->len;
   u_int hlen, off, version;
   
   int len;

   ip =(struct my_ip*)(packet+sizeof(struct ether_header));
   length-=sizeof(struct ether_header);

   // if IP hdr is smaller than the normal
   if(length < sizeof(struct my_ip)){
      printf("truncated ip %d",length);
      return -1;
   }

   len =ntohs(ip->ip_len);
   hlen =IP_HL(ip);
   version =IP_V(ip);

   if(version != 4){
      printf("Unknown version\n");
      return -1;
   }

   if(hlen < 5){
      printf("error in IHL\n");
      return -1;
   }

   if(length < len)
      printf("\ntruncated IP - %d bytes missing\n", len-length);
   off =ntohs(ip->ip_off);
   
   printf("IP: ");
   printf("%s ",inet_ntoa(ip->ip_src));
   printf("%s %d %d %d %d\n",inet_ntoa(ip->ip_dst),hlen,version,
         len,off);

   return (uint16_t)ip->ip_p;
}

int main(int argc, char **argv){
   
   char *dev;
   char errbuf[PCAP_ERRBUF_SIZE];
   
   pcap_t* descr;
   char *filter_exp;

   int num_pkts_exp;

   if(argc < 4) {
      printf("error: number of arguments invalid. Expected: iface 'expression'\n");
      exit(-1);
   }  

   dev = argv[1]; //dev = pcap_lookupdev(errbuf);
   filter_exp = argv[2];   
   num_pkts_exp = atoi(argv[3]);

   if(dev == NULL){
      printf("error: %s\n",errbuf);
      exit(1);
   }

   printf("device: %s\n",dev);

   // IP and maks of sniffing device   
   bpf_u_int32 net, mask;
   if(pcap_lookupnet(dev,&net,&mask,errbuf) == -1){
      printf("Error: lookupnet\n");
      exit(-1);
   }

    // open for sniffing
   descr = pcap_open_live(dev,BUFSIZ,0,-1,errbuf);
     
   if(descr == NULL){
      printf("pcap_open_live(): %s\n",errbuf);
      exit(-1);
   }

   // the compiled filter expression
   struct bpf_program fp; 
   if(pcap_compile(descr,&fp,filter_exp,0,mask) == -1){
      printf("Couldn't parses the filter  %s\n",pcap_geterr(descr));
      exit(-1);
   }
   printf("filter expr\n");

   if(pcap_setfilter(descr,&fp) == -1){
      printf("Couldn't parses the filter  %s\n",pcap_geterr(descr));
      exit(-1);
   }

   pcap_loop(descr,num_pkts_exp,my_callback,NULL);

   pcap_close(descr);
   return 0;

}
