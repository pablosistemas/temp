///////////////////////////////////////////////////////////////////////////////
// vim:set shiftwidth=3 softtabstop=3 expandtab:
// $Id: evt_capture_regs.v 5639 2009-06-02 18:24:51Z grg $
//
// Module: cria_pkts.v
// Project: event capture
// Description: Has registers to control event capture
//
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module cria_pkts 
  #(parameter DATA_WIDTH = 64,
    parameter CTRL_WIDTH = DATA_WIDTH/8,
    parameter UDP_REG_SRC_WIDTH = 2,
    parameter NUM_MONITORED_SIGS = 3,
    parameter SIGNAL_ID_SIZE = 3,
    parameter NUM_ABS_REG_PAIRS    = 4,
    parameter TIMER_RES_SIZE = 3,
    parameter HEADER_LENGTH = 7,
    parameter OP_LUT_STAGE_NUM = 4,
    parameter NUM_WORDS_PAYLOAD =8,
    parameter HEADER_LENGTH_SIZE = log2(HEADER_LENGTH),
    parameter NUM_MON_SIGS_SIZE  = log2(NUM_MONITORED_SIGS+2))

    ( // register interface
      input                                  reg_req_in,
      input                                  reg_ack_in,
      input                                  reg_rd_wr_L_in,
      input  [`UDP_REG_ADDR_WIDTH-1:0]       reg_addr_in,
      input  [`CPCI_NF2_DATA_WIDTH-1:0]      reg_data_in,
      input  [UDP_REG_SRC_WIDTH-1:0]         reg_src_in,

      output reg                             reg_req_out,
      output reg                             reg_ack_out,
      output reg                             reg_rd_wr_L_out,
      output reg [`UDP_REG_ADDR_WIDTH-1:0]   reg_addr_out,
      output reg [`CPCI_NF2_DATA_WIDTH-1:0]  reg_data_out,
      output reg [UDP_REG_SRC_WIDTH-1:0]     reg_src_out,


      // interface to 
      input [HEADER_LENGTH_SIZE-1:0]       header_word_number, // number of header word requested
      input                                evt_pkt_sent,       // pulses high when a pkt is sent
      output [DATA_WIDTH-1:0]              header_data,        // header data at header_word_number
      output [CTRL_WIDTH-1:0]              header_ctrl,        // header ctrl at header_word_number
      output                               enable,

      // misc
      input clk,
      input reset);

   function integer log2;
      input integer number;
      begin
         log2=0;
         while(2**log2<number) begin
            log2=log2+1;
         end
      end
   endfunction // log2

   function integer calcprecheck;
      input reg[7:0] ip_ttl;
      input reg[7:0] udp_proto;

      integer temp;
      begin
         temp = 16'h4500; // ip ver/hdr_len/tos
         temp = temp + 1; // id
         temp = temp + 0; // flags+offset
         temp = temp + {ip_ttl, udp_proto}; // TTL, udp proto
         temp = temp[15:0] + temp[31:16];
         if(temp[31:16] != 0) $display("ERROR: constant checksum calculation wrong!");
         calcprecheck = temp;
      end
   endfunction // reg

   //-------------------- Local parameters ------------------------
   localparam NUM_REGS_USED  = 12;
   localparam ADDR_WIDTH     = log2(NUM_REGS_USED);
   localparam IP_TTL = 8'h64;
   localparam UDP_PROTO = 8'd17;
   localparam CONSTANT_PRECHECK = calcprecheck(IP_TTL, UDP_PROTO);

   localparam UPDATE_PRECHECK   = 1;
   localparam UPDATE_PRECHECK_0 = 2;
   localparam UPDATE_PRECHECK_1 = 4;
   localparam UPDATE_PRECHECK_2 = 8;
   localparam UPDATE_PRECHECK_3 = 16;
   localparam PRECHECK_DONE     = 32;


   //---------------- Wire and Reg Declarations -------------------
   reg [`CPCI_NF2_DATA_WIDTH-1:0] reg_file [0:NUM_REGS_USED-1];

   wire [ADDR_WIDTH-1:0]         addr;
   wire [`MAKER_REG_ADDR_WIDTH - 1:0] reg_addr;
   wire [`MAKER_BLOCK_ADDR_WIDTH-1:0] tag_addr;

   wire                          addr_good;
   wire                          tag_hit;

   wire [DATA_WIDTH-1:0]         header_words [HEADER_LENGTH-1:0];

   wire [11:0] 			         pkt_data_len;
   wire [15:0] 			         udp_pkt_len, ip_pkt_len, eth_pkt_len;
   wire [8:0]                    eth_pkt_word_len;

   integer                       i;

   wire [15:0]                   dst_mac_hi;
   wire [31:0]                   dst_mac_lo;
   wire [15:0]                   src_mac_hi;
   wire [31:0]                   src_mac_lo;
   wire [15:0]                   ethertype;
   wire [31:0]                   dst_ip_addr;
   wire [31:0]                   src_ip_addr;
   wire [15:0]                   udp_src_port, udp_dst_port;
   wire [31:0]                   out_ports;

   reg [15:0]                    ip_chksum;
   reg [16:0]                    checksum_temp;
   reg [5:0]                     chksum_state;
   reg [18:0]                    precheck;

   wire [DATA_WIDTH-1:0]         module_hdr;

   //---------------------- Logic -------------------------------

   assign addr           = reg_addr_in[ADDR_WIDTH-1:0];
   assign reg_addr       = reg_addr_in[`MAKER_REG_ADDR_WIDTH-1:0];
   assign tag_addr       = reg_addr_in[`UDP_REG_ADDR_WIDTH - 1:`MAKER_REG_ADDR_WIDTH];

   assign addr_good      = (reg_addr < NUM_REGS_USED);
   assign tag_hit        = tag_addr == `MAKER_BLOCK_ADDR;

   /* get the info from the registers */
   assign dst_mac_hi     = reg_file[`MAKER_DST_MAC_HI];
   assign dst_mac_lo     = reg_file[`MAKER_DST_MAC_LO];
   assign src_mac_hi     = reg_file[`MAKER_SRC_MAC_HI];
   assign src_mac_lo     = reg_file[`MAKER_SRC_MAC_LO];
   assign ethertype      = reg_file[`MAKER_ETHERTYPE];
   assign dst_ip_addr    = reg_file[`MAKER_IP_DST];
   assign src_ip_addr    = reg_file[`MAKER_IP_SRC];
   assign udp_src_port   = reg_file[`MAKER_UDP_SRC_PORT];
   assign udp_dst_port   = reg_file[`MAKER_UDP_DST_PORT];
   assign out_ports      = reg_file[`MAKER_OUTPUT_PORT];
   assign enable         = reg_file[`MAKER_ENABLE];

   /* calculate the pkt lengths to put in hdrs */
   //assign pkt_data_len    = {num_evts_in_pkt, 2'b0} + (8*NUM_ABS_REG_PAIRS + 6); // 6 = evt_pkt hdr length
   assign pkt_data_len     = {NUM_WORDS_PAYLOAD,3'b0}+6; //chksum+6(payload) devem ser contados bytes
   assign udp_pkt_len      = pkt_data_len+4'd8;
   assign ip_pkt_len       = pkt_data_len+6'd28;
   assign eth_pkt_len      = pkt_data_len+6'd42;
   /* check if adding the headers would lead to a word-aligned packet */
   //assign eth_pkt_word_len= (pkt_data_len[2:0]==6) ? eth_pkt_len[11:3] : eth_pkt_len[11:3]+1'b1;
   assign eth_pkt_word_len= NUM_WORDS_PAYLOAD+HEADER_LENGTH-1;

   /* set the module header */
   assign module_hdr [`IOQ_BYTE_LEN_POS + 15:`IOQ_BYTE_LEN_POS] = eth_pkt_len;
   assign module_hdr [`IOQ_WORD_LEN_POS + 15:`IOQ_WORD_LEN_POS] = {7'b0, eth_pkt_word_len};
   assign module_hdr [`IOQ_SRC_PORT_POS + 15:`IOQ_SRC_PORT_POS] = 16'hffff;
/* OutputPortLookup NIC-based automatically fill the 
   * destination port on header based on src port.  
   * Odd number in SRC port means the pkt came from cpu
   * */   
   assign module_hdr [`IOQ_DST_PORT_POS + 15:`IOQ_DST_PORT_POS] = out_ports[15:0];

   /* set the header words */
   assign header_words[0] = module_hdr;
   assign header_words[1] = {dst_mac_hi[15:0], dst_mac_lo, src_mac_hi[15:0]};
   assign header_words[2] = {src_mac_lo, ethertype[15:0], 4'h4, 4'h5, 8'h0};
   assign header_words[3] = {ip_pkt_len, 16'h1, 16'h0, IP_TTL, UDP_PROTO};
   assign header_words[4] = {ip_chksum[15:0], src_ip_addr, dst_ip_addr[31:16]};
   assign header_words[5] = {dst_ip_addr[15:0], udp_src_port[15:0], udp_dst_port[15:0], udp_pkt_len};
   assign header_words[6] = {64'h0};
   //assign header_words[6] = {16'h0, 4'h0, EVT_CAPTURE_VERSION, NUM_MONITORED_SIGS[7:0], reg_file[`EVT_CAP_NUM_EVT_PKTS_SENT]};

   /* select the header word */
   assign header_data = header_words[header_word_number];
   assign header_ctrl = (header_word_number==0) ? `IO_QUEUE_STAGE_NUM : 0;

   always @(posedge clk) begin
      // Never modify the address/src
      reg_rd_wr_L_out <= reg_rd_wr_L_in;
      reg_addr_out <= reg_addr_in;
      reg_src_out <= reg_src_in;

      if(reset) begin
         reg_req_out                     <= 1'b0;
         reg_ack_out                     <= 1'b0;
         reg_data_out                    <= 'h0;

         for(i=0; i<NUM_REGS_USED; i=i+1) begin
            reg_file[i] <= 0;
         end

         chksum_state <= UPDATE_PRECHECK;

      end
      else begin
         // Register accesses
         if(reg_req_in && tag_hit) begin
            if(addr_good) begin
               reg_data_out <= reg_file[addr];

               if (!reg_rd_wr_L_in)
                  reg_file[addr] <= reg_data_in;
            end
            else begin
               reg_data_out <= 32'hdead_beef;
            end

            reg_ack_out <= 1'b1;
         end
         else begin
            reg_ack_out <= reg_ack_in;
            reg_data_out <= reg_data_in;
         end
         reg_req_out <= reg_req_in;


         if(evt_pkt_sent) begin
            reg_file[`MAKER_NUM_EVT_PKTS_SENT]    <= reg_file[`MAKER_NUM_EVT_PKTS_SENT] + 1;
            //reg_file[`MAKER_NUM_EVTS_SENT]        <= reg_file[`MAKER_NUM_EVTS_SENT] + num_evts_in_pkt;
         end
         //reg_file[`EVT_CAP_NUM_EVTS_DROPPED] <= reg_file[`EVT_CAP_NUM_EVTS_DROPPED] + evts_dropped;

         /* update the precaluclated partial checksum when
          * the ip addresses are changed */
         case(chksum_state)
            UPDATE_PRECHECK: begin
               precheck     <= CONSTANT_PRECHECK[15:0]+src_ip_addr[31:16];
               chksum_state <= UPDATE_PRECHECK_0;
            end

            UPDATE_PRECHECK_0: begin
               precheck     <= precheck[15:0] + src_ip_addr[15:0];
               chksum_state <= UPDATE_PRECHECK_1;
            end

            UPDATE_PRECHECK_1: begin
               precheck     <= precheck + dst_ip_addr[15:0];
               chksum_state <= UPDATE_PRECHECK_2;
            end

            UPDATE_PRECHECK_2: begin
               precheck     <= precheck + dst_ip_addr[31:16];
               chksum_state <= UPDATE_PRECHECK_3;
            end

            UPDATE_PRECHECK_3: begin
               precheck     <= precheck[15:0] + precheck[18:16];
               chksum_state <= PRECHECK_DONE;
            end

            PRECHECK_DONE: begin
               // synthesis translate off
               if(precheck[18:16] != 0) begin
                  $display("%t %m ERROR: Pre-checksum calculation is wrong!", $time);
                  $stop;
               end
               // synthesis translate on
               if(reg_req_in && tag_hit && addr_good && !reg_rd_wr_L_in &&
                  (addr==`MAKER_IP_DST || addr==`MAKER_IP_SRC)) begin
                  chksum_state <= UPDATE_PRECHECK;
               end
            end

         endcase // case(chksum_state)

         /* calculate the checksum */
         checksum_temp <= ip_pkt_len + precheck[15:0];
         ip_chksum <= ~(checksum_temp[15:0] + checksum_temp[16]);

      end // else: !if(reset)
   end // always @ (posedge clk)

   // synthesis translate off

   integer sim_chksum;
   always @(*) begin
      sim_chksum =
           {4'h4, 4'h5, 8'h0} +
           ip_pkt_len +
           16'h1 +
           16'h0 +
           {IP_TTL, UDP_PROTO} +
           src_ip_addr[31:16] +
           src_ip_addr[15:0] +
           dst_ip_addr[31:16] +
           dst_ip_addr[15:0];

      sim_chksum = ~(sim_chksum[31:16]+sim_chksum[15:0]);
   end // always @ (*)

   // synthesis translate on
   
   // synthesis translate off
   always @(*) begin
      if(reg_req_in && tag_hit && addr_good && 
         !reg_rd_wr_L_in)
            $display("reg_file[%d]: %h\n",addr,reg_data_in);
   end
   // synthesis translate on

endmodule // cria_pkts
