#
# $Id: Makefile 6042 2010-04-01 05:59:23Z grg $
#

CFLAGS = -g
CC = gcc
LDFLAGS = -lncurses

all : registers counterdump

registers:
	$(NF_ROOT)/bin/nf_register_gen.pl --project reference_nic

counterdump : counterdump.o ../../../lib/C/common/nf2util.o ../../../lib/C/common/nf2util_proxy_common.o ../lib/C/reg_defines_temp.h

clean :
	rm -f counterdump *.o ../../../lib/C/common/nf2util.o ../../../lib/C/common/nf2util_proxy_common.o
	rm -f libnetuno libnetunoack

libnet : libnet.c
	gcc -Wall libnet.c -I/usr/include/libnet -o libnet /usr/lib/libnet.so

codump : counterdump.c
	gcc -Wall counterdump.c -I/usr/include/ -o counterdump /root/netfpga/lib/C/common/libnf2.so

cdump : cdump.c
	gcc -Wall cdump.c -I/usr/include/ -o cdump /root/netfpga/lib/C/common/libnf2.so

readsram: readsram.c
	gcc -Wall readsram.c -I/usr/include/ -o readsram /root/netfpga/lib/C/common/libnf2.so

readsrambign: readsrambign.c
	gcc -Wall readsrambign.c -I/usr/include/ -lgmp -o readsrambign /root/netfpga/lib/C/common/libnf2.so

install:

.PHONY: all clean install
