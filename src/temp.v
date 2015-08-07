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
      parameter SRAM_DATA_WIDTH = DATA_WIDTH+CTRL_WIDTH,
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
   localparam NUM_STATES = 7; //ONE_HOT ENCODING

   localparam ICMP = 'h01;
   localparam TCP = 'h06;
   localparam UDP = 'h11;
   localparam SCTP = 'h84;

   localparam ETH_TYPE_IP = 16'h0800;
   localparam IPV4 = 4'h4; 

   wire [DATA_WIDTH-1:0]                     in_fifo_data;
   wire [CTRL_WIDTH-1:0]                     in_fifo_ctrl;

   wire                                      in_fifo_full;
   wire                                      in_fifo_empty;
   reg                                       in_fifo_rd_en;

   reg [NUM_STATES-1:0]                      state, state_next;
      
   reg [31:0]                                num_TCP, num_TCP_next;

   //------------------------- Local assignments -------------------------------

   assign in_rdy     = !in_fifo_full;

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

   //------------------------- Logic-------------------------------
   //

   assign reg_req_out = reg_req_in;
   assign reg_ack_out = reg_ack_in;
   assign reg_rd_wr_L_out = reg_rd_wr_L_in;
   assign reg_addr_out = reg_addr_in;
   assign reg_data_out = reg_data_in;
   assign reg_src_out = reg_src_in;

   assign out_ctrl = in_fifo_ctrl;
   assign out_data = in_fifo_data;

   always @(*) begin
      // Default values
      in_fifo_rd_en = 0;
      out_wr = 0;
      
      state_next = state;
      
      num_TCP = num_TCP_next;

      case(state)
      WAIT_PACKET: begin
         if (!in_fifo_empty && out_rdy) begin
            in_fifo_rd_en = 1;
            out_wr = 1;
            if(in_fifo_ctrl == 8'h00) begin
               state_next = WORD2_CHECK_IPV4;
            end else begin
               state_next = WAIT_PACKET;
            end
         end
         else
            state_next = WAIT_PACKET;
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
         else
            state_next = WORD2_CHECK_IPV4;
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
         end
         else
            state_next = WORD3_CHECK_TCP;
      end
      WORD4_ADDR_CHKSUM: begin
         if (!in_fifo_empty && out_rdy) begin
            in_fifo_rd_en = 1;
            out_wr = 1;
            state_next = WORD5_TCP_PORT;
         end
         else
            state_next = WORD4_ADDR_CHKSUM;
      end
      WORD5_TCP_PORT: begin
         if (!in_fifo_empty && out_rdy) begin
            in_fifo_rd_en = 1;
            out_wr = 1;
            state_next = WORD6_TCP_ACK;
         end
         else
            state_next = WORD5_TCP_PORT;
      end
      WORD6_TCP_ACK: begin
         state_next = PAYLOAD;
      end
      PAYLOAD: begin
         if (!in_fifo_empty && out_rdy) begin
            in_fifo_rd_en = 1;
            out_wr = 1;
            if(in_fifo_ctrl != `IO_QUEUE_STAGE_NUM) begin
               state_next = PAYLOAD;
            end
            else if(in_fifo_ctrl == `IO_QUEUE_STAGE_NUM) begin
               out_wr = 0;
               in_fifo_rd_en = 0;
               state_next = WAIT_PACKET;
            end
         end
         else
            state_next = PAYLOAD;
      end
      endcase
   end

   always @(posedge clk) begin
      if(reset) begin
         state <= WAIT_PACKET;
         num_TCP <= 0;
      end
      else begin
         state <= state_next;
         num_TCP <= num_TCP_next;
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

   end
   //synthesis translate_on
endmodule
