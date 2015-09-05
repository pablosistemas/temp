///////////////////////////////////////////////////////////////////////////////
// vim:set shiftwidth=3 softtabstop=3 expandtab:
// $Id: module_template 2008-03-13 gac1 $
//
// Module: temp.v
// Project:TEMP 
// Description: Maquina de estados TCP.
//
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module temp 
   #(
      parameter DATA_WIDTH = 64,
      parameter CTRL_WIDTH = DATA_WIDTH/8,
      parameter SRAM_ADDR_WIDTH = 19,
      parameter HASH_BITS = SRAM_ADDR_WIDTH,
      parameter TUPLE_SZ =128, //2IP, 2PORT, seqno/ackno
      parameter UDP_REG_SRC_WIDTH = 2
   )
   (
      input  [DATA_WIDTH-1:0]             in_data,
      input  [CTRL_WIDTH-1:0]             in_ctrl,
      input                               in_wr,
      output                              in_rdy,

      output [DATA_WIDTH-1:0]             out_data,
      output [CTRL_WIDTH-1:0]             out_ctrl,
      output reg                          out_wr,
      input                               out_rdy,

      /* --- interface to bloom filter --- */
      input                               bloom_rdy,
      output reg                          bloom_wr,   
      output [HASH_BITS-1:0]              index_0,
      output [HASH_BITS-1:0]              index_1,
      output [95:0]                       wire_tuple,
      output reg                          pkt_is_ack,         

      // --- Register interface
      input                               reg_req_in,
      input                               reg_ack_in,
      input                               reg_rd_wr_L_in,
      input  [`UDP_REG_ADDR_WIDTH-1:0]    reg_addr_in,
      input  [`CPCI_NF2_DATA_WIDTH-1:0]   reg_data_in,
      input  [UDP_REG_SRC_WIDTH-1:0]      reg_src_in,

      output                              reg_req_out,
      output                              reg_ack_out,
      output                              reg_rd_wr_L_out,
      output  [`UDP_REG_ADDR_WIDTH-1:0]   reg_addr_out,
      output  [`CPCI_NF2_DATA_WIDTH-1:0]  reg_data_out,
      output  [UDP_REG_SRC_WIDTH-1:0]     reg_src_out,

      // misc
      input                                reset,
      input                                clk
   );

   // Define the log2 function
   `LOG2_FUNC

   //------------------------- Signals-------------------------------
   
   localparam WAIT_PACKET =1;
   localparam WORD2_CHECK_IPV4 =2;
   localparam WORD3_CHECK_TCP =4;
   localparam WORD4_ADDR_CHKSUM =8;
   localparam WORD5_TCP_PORT =16;
   localparam WORD6_TCP_ACK = 32;
   localparam PAYLOAD =64;
   localparam BLOOM_CTRL =128;
   localparam NUM_STATES = 8; //ONE_HOT ENCODING

   localparam TCP = 'h06;
   
   localparam ETH_TYPE_IP = 16'h0800;
   localparam IPV4 = 4'h4; 

   wire [DATA_WIDTH-1:0]                     in_fifo_data;
   wire [CTRL_WIDTH-1:0]                     in_fifo_ctrl;

   wire                                      in_fifo_full;
   wire                                      in_fifo_empty;
   reg                                       in_fifo_rd_en;

   reg [NUM_STATES-1:0]                      state, state_next;
      
   reg [31:0]                                num_TCP, num_TCP_next;
   
   /* hash tuple: wires and regs */
   reg  [TUPLE_SZ-1:0]			               tuple;
   
   reg[31:0]       			         srcip_next, srcip;
   reg[31:0]			               dstip_next, dstip;
   reg[15:0]			               srcport_next, srcport;
   reg[15:0]	   		            dstport_next, dstport;
   reg[31:0]                        seqno, seqno_next;
   reg[31:0]                        ackno, ackno_next;
   reg[15:0]                        pld_len, pld_len_next;
   
   reg                                       pkt_is_ack_next;
   


   //------------------------- Local assignments -------------------------------

   assign in_rdy     = !in_fifo_full;
   
   assign reg_req_out = reg_req_in;
   assign reg_ack_out = reg_ack_in;
   assign reg_rd_wr_L_out = reg_rd_wr_L_in;
   assign reg_addr_out = reg_addr_in;
   assign reg_data_out = reg_data_in;
   assign reg_src_out = reg_src_in;

   assign out_ctrl = in_fifo_ctrl;
   assign out_data = in_fifo_data;

   assign wire_tuple = tuple[95:0];

   //always @(dstport,srcport,dstip,srcip,pkt_is_ack_next,pkt_is_ack) begin
   always @(*) begin
      if (pkt_is_ack) begin
         tuple[15:0] =dstport;
         tuple[31:16] =srcport;
         tuple[63:32] =dstip;
         tuple[95:64] =srcip;
         tuple[127:96] =ackno;
      end 
      else begin
         tuple[15:0] =srcport;
         tuple[31:16] =dstport;
         tuple[63:32] =srcip;
         tuple[95:64] =dstip;
         tuple[127:96] =seqno+{16'b0,pld_len}+32'b1;
      end
   end

   //------------------------- Modules-------------------------------

   fallthrough_small_fifo_old #(
      .WIDTH(CTRL_WIDTH+DATA_WIDTH),
      .MAX_DEPTH_BITS(3)
   ) input_fifo (
      .din           ({in_ctrl, in_data}),   // Data in
      .wr_en         (in_wr),                // Write enable
      .rd_en         (in_fifo_rd_en),        // Read the next word
      .dout          ({in_fifo_ctrl, in_fifo_data}),
      .full          (in_fifo_full),
      .nearly_full   (),
      .empty         (in_fifo_empty),
      .reset         (reset),
      .clk           (clk)
   );

   hash
     #(.INPUT_WIDTH   (TUPLE_SZ),
       .OUTPUT_WIDTH  (19))
       tuple_hash
         (.data              (tuple),
          .hash_0            (index_0),
          .hash_1            (index_1));

   //------------------------- Logic-------------------------------
   
   always @(*) begin
      // Default values
      in_fifo_rd_en = 0;
      out_wr = 0;

      /* Bloom interface */
      bloom_wr = 0;

      state_next = state;
      num_TCP_next = num_TCP;

      pkt_is_ack_next = pkt_is_ack;
      pld_len_next = pld_len;
      
      srcip_next = srcip;
      dstip_next = dstip;
      srcport_next = srcport;
      dstport_next = dstport; 
      seqno_next = seqno;
      ackno_next = ackno;
      
      case(state)
      WAIT_PACKET: begin
         if (!in_fifo_empty && out_rdy) begin
            in_fifo_rd_en = 1;
            out_wr = 1;
            if(in_fifo_ctrl == 8'h00) begin
               pkt_is_ack_next = 0;
               state_next = WORD2_CHECK_IPV4;
            end else begin
               state_next = WAIT_PACKET;
            end
         end
      end
      WORD2_CHECK_IPV4: begin
         if (!in_fifo_empty && out_rdy) begin
            in_fifo_rd_en = 1;
            out_wr = 1;
            if(in_fifo_data[31:16] != ETH_TYPE_IP ||
                  in_fifo_data[15:12] != IPV4) begin
               state_next = PAYLOAD;
            end
            else begin
               state_next = WORD3_CHECK_TCP;
            end
         end
      end
      WORD3_CHECK_TCP: begin
         if (!in_fifo_empty && out_rdy) begin
            in_fifo_rd_en = 1;
            out_wr = 1;
            if(in_fifo_data[7:0] == TCP) begin
               num_TCP_next = num_TCP + 'h1;
               state_next = WORD4_ADDR_CHKSUM;
            end
            else begin
               state_next = PAYLOAD;
            end
            pld_len_next =in_fifo_data[63:48];
         end
      end
      WORD4_ADDR_CHKSUM: begin
         if (!in_fifo_empty && out_rdy) begin
            in_fifo_rd_en = 1;
            out_wr = 1;
            state_next = WORD5_TCP_PORT;
            /* tupla */
            srcip_next = in_fifo_data[47:16]; //srcIP
            dstip_next[31:16] = {in_fifo_data[15:0]}; //dstIP1
         end
      end
      WORD5_TCP_PORT: begin
         if (!in_fifo_empty && out_rdy) begin
            in_fifo_rd_en = 1;
            out_wr = 1;
            state_next = WORD6_TCP_ACK;

            /* tupla */
            dstip_next[15:0] = in_fifo_data[63:48]; //dstIP2
            srcport_next = in_fifo_data[47:32]; //srcPort
            dstport_next = in_fifo_data[31:16]; //dstPort
            seqno_next[31:16]=in_fifo_data[15:0];
         end
      end
      WORD6_TCP_ACK: begin
         if (!in_fifo_empty && out_rdy) begin
            in_fifo_rd_en = 1;
            out_wr = 1;
           
            //tupla
            seqno_next[15:0] = in_fifo_data[63:48];
            ackno_next = in_fifo_data[47:16];
            // subtract ip(0x14) and tcp(offset*4) headers
            pld_len_next = pld_len - 16'd20 - {(16){in_fifo_data[15:12]*4}};

            if(in_fifo_data[4]) begin
               pkt_is_ack_next = 1'b1;
            end

            state_next = BLOOM_CTRL;         
         end
      end
      BLOOM_CTRL: begin
         if (bloom_rdy) begin
            bloom_wr = 1;
            state_next = PAYLOAD;
         end
      end
      PAYLOAD: begin
         if (!in_fifo_empty && out_rdy) begin
            if(in_fifo_ctrl != `IO_QUEUE_STAGE_NUM) begin
               in_fifo_rd_en = 1;
               out_wr = 1;
               state_next = PAYLOAD;
            end else if (in_fifo_ctrl == `IO_QUEUE_STAGE_NUM)
               state_next = WAIT_PACKET; 
         end
      end
      endcase
   end

   always @(posedge clk) begin
      if(reset) begin
         state <= WAIT_PACKET;
         num_TCP <= 0;
         pkt_is_ack <= 0;
        
         //tupla 
         srcip <= 32'h0;
         dstip <= 32'h0;
         srcport <= 16'h0;
         dstport <= 16'h0; 
         seqno <= 32'h0;
         ackno <=32'h0;
         pld_len <=16'h0;

      end else begin
         state <= state_next;
         num_TCP <= num_TCP_next;
         
         /* tupla */ 
         pkt_is_ack <= pkt_is_ack_next;    
         srcip <= srcip_next;
         dstip <= dstip_next;
         srcport <= srcport_next;
         dstport <= dstport_next; 
         seqno <= seqno_next;
         ackno <= ackno_next;
         pld_len <=pld_len_next;
      end
   end

         
   /* DEBUG */
   //synthesis translate_off
   always @(posedge clk) begin
      if(in_fifo_data[31:16] == ETH_TYPE_IP &&
            in_fifo_data[15:12] == IPV4)
         $display("WORD2_CHECK_IPV4: pacote IPV4\n");

      if(in_fifo_data[7:0] == TCP)
         $display("WORD3_CHECK_TCP: TCP\n");
      
      if(state_next == BLOOM_CTRL) begin
         $display("BLOOM_CTRL\n");
         $display("seqno: %d\n",seqno_next);
         $display("ackno: %d\n",ackno_next);
         $display("pldlen: %d\n",pld_len_next);
      end

      /*if(state_next == WAIT_PACKET)
         $display("WAIT_PACKET\n");*/

      if(state_next == WORD5_TCP_PORT)
         $display("WORD5_TCP_PORT\n");

      if(state_next == WORD4_ADDR_CHKSUM)
         $display("WORD4_ADDR_CHKSUM\n");

      if(state_next == WORD6_TCP_ACK)
         $display("WORD6_TCP_ACK\n");
      /*if(state_next == PAYLOAD)
         $display("PAYLOAD\n");*/

      //if(state == PAYLOAD && state_next == WAIT_PACKET) begin
     
      if(bloom_wr) begin
         $display("tupla: %h\n",tuple);
         $display("hash0: %h\nhash1: %h\n",index_0,index_1); 
      end
      if(!bloom_rdy)
         $stop;

      if(state_next == WORD6_TCP_ACK && in_fifo_data[4])
         $display("ACK\n");
      else if(state_next == WORD6_TCP_ACK)
         $display("NACK\n");

   end
   //synthesis translate_on
endmodule
