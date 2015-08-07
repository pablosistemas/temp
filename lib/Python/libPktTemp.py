#!/usr/bin/env python

from NFTest import *

try:
    import scapy.all as scapy
except:
    try:
        import scapy as scapy
    except:
        sys.exit("Error: Need to install scapy for packet handling")

############################
# Function: make_TCP_hdr
# Keyword Arguments: src_PORT, dst_PORT, seq_NUM
# Description: creates and returns a scapy Ether layer
#              if keyword arguments are not specified, scapy defaults are used
############################
def make_TCP_hdr(src_PORT = None, dst_PORT = None, seq_NUM = None,**kwargs):
    hdr = scapy.TCP()
    if src_PORT:
        hdr[scapy.TCP].sport = src_PORT
    if dst_PORT:
        hdr[scapy.TCP].dport = dst_PORT
    if seq_NUM:
        hdr[scapy.TCP].seq = seq_NUM
    return hdr


############################
# Function: make_TCP_pkt
# Keyword Arguments: src_MAC, dst_MAC, EtherType
#                    src_IP, dst_IP, TTL, src_PORT, dst_PORT, seq_NUM
#                    pkt_len
# Description: creates and returns a complete IP packet of length pkt_len
############################
def make_TCP_pkt(pkt_len = 60, **kwargs):
    if pkt_len < 60:
        pkt_len = 60
    pkt = make_MAC_hdr(**kwargs)/make_IP_hdr(**kwargs)/make_TCP_hdr(**kwargs)/generate_load(pkt_len - 54)
    return pkt


############################
# Function: make_UDP_hdr
# Keyword Arguments: src_PORT, dst_PORT
# Description: creates and returns a scapy Ether layer
#              if keyword arguments are not specified, scapy defaults are used
############################
def make_UDP_hdr(src_PORT = None, dst_PORT = None,**kwargs):
    hdr = scapy.UDP()
    if src_PORT:
        hdr[scapy.UDP].sport = src_PORT
    if dst_PORT:
        hdr[scapy.UDP].dport = dst_PORT
    return hdr


############################
# Function: make_UDP_pkt
# Keyword Arguments: src_MAC, dst_MAC, EtherType
#                    src_IP, dst_IP, TTL, src_PORT, dst_PORT,
#                    pkt_len
# Description: creates and returns a complete IP packet of length pkt_len
############################
def make_UDP_pkt(pkt_len = 60, **kwargs):
    if pkt_len < 60:
        pkt_len = 60
    pkt = make_MAC_hdr(**kwargs)/make_IP_hdr(**kwargs)/make_UDP_hdr(**kwargs)/generate_load(pkt_len - 54)
    return pkt

