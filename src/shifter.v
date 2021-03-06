///////////////////////////////////////////////////////////////////////////////
// vim:set shiftwidth=3 softtabstop=3 expandtab:
// $Id: module_template 2008-03-13 gac1 $
//
// Module: temp.v
// Project:TEMP 
// Description: This state machine only does shifts in memory.
//
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module shifter
   #(
      parameter SRAM_ADDR_WIDTH = 19,
      parameter SRAM_DATA_WIDTH = 72,
      parameter NUM_REQS = 5,
      parameter ADDR_SHIFT = 2**SRAM_ADDR_WIDTH
   ) (

      output reg                          	wr_shi_req,
      output reg [SRAM_ADDR_WIDTH-1:0]    	wr_shi_addr,
      output reg [SRAM_DATA_WIDTH-1:0]    	wr_shi_data,
      input                               	wr_shi_ack,

      output reg                          	rd_shi_req,
      output reg [SRAM_ADDR_WIDTH-1:0]    	rd_shi_addr,
      input [SRAM_DATA_WIDTH-1:0]         	rd_shi_data,
      input                               	rd_shi_ack,
      input                               	rd_shi_vld,

      /* watchdog */ 
      input                                  watchdog_signal,

      // misc
      input                                	reset,
      input                                	clk
   );

   /* ----------Estados----------*/

	localparam SRAM_READ = 1;
	localparam SRAM_WRITE = 2;
   localparam WAIT_WATCHDOG = 4;
   localparam WAIT_READ = 8;
   localparam WAIT_WRITE =16;
	
	localparam NUM_STATES = 5;
   localparam NUM_BITS_REQS = log2(NUM_REQS);

   localparam HASH_FIFO_DATA_WIDTH = 1 + 2*SRAM_ADDR_WIDTH;
   localparam SRAM_FIFO_DATA_WIDTH = SRAM_DATA_WIDTH;

   // Define the log2 function
   `LOG2_FUNC

   /* interface to SRAM */
   reg [SRAM_DATA_WIDTH-1:0]					wr_shi_data_next;
   reg [SRAM_ADDR_WIDTH-1:0]					wr_shi_addr_next;
	reg												wr_shi_req_next;
   reg [SRAM_ADDR_WIDTH-1:0]					rd_shi_addr_next;
	reg												rd_shi_req_next;
   
	reg [NUM_STATES-1:0]							state, state_next;
	reg [NUM_BITS_REQS-1:0]                reqs, reqs_next;

   /* FIFO ctrl */
   reg                                    in_fifo_shift_rd_en;
   wire                                   in_fifo_shift_wr;
   wire                                   in_fifo_shift_full;
   wire                                   in_fifo_shift_empty;
   wire [SRAM_FIFO_DATA_WIDTH-1:0]        in_fifo_shift_dout;
   

	/* ----------- local assignments -----------*/
   
   assign in_fifo_shift_wr = rd_shi_vld && !in_fifo_shift_full;

	/* --------------instances of external modules------------------ */
	
   /* fifo holds data read from sram */
   fallthrough_small_fifo #(
   		.WIDTH(SRAM_FIFO_DATA_WIDTH), 
   		.MAX_DEPTH_BITS(3)) in_fifo_shift_module 
        (.din ({rd_shi_data}), // Data in
         .wr_en (in_fifo_shift_wr), // Write enable
         .rd_en (in_fifo_shift_rd_en), // Read the next word 
         .dout ({in_fifo_shift_dout}),
         .full (in_fifo_shift_full),
         .nearly_full (),
         .empty (in_fifo_shift_empty),
         .reset (reset),
         .clk (clk));
 
   /*  */
	 always @(*) begin
      in_fifo_shift_rd_en = 0; 
	 	/* SRAM */
	 	{rd_shi_req_next, wr_shi_req_next} = 2'b0;
	 	rd_shi_addr_next = rd_shi_addr;
      wr_shi_addr_next = wr_shi_addr;
	 	wr_shi_data_next = wr_shi_data;
	 	
      state_next = state;
      reqs_next = reqs;

	 	case(state)
	 		SRAM_READ: begin
	 		if(!in_fifo_shift_full) begin
            if(rd_shi_addr == ({(SRAM_ADDR_WIDTH){1'b1}}-1))
               state_next = WAIT_WATCHDOG;
            else begin
               rd_shi_req_next = 1;
               state_next = WAIT_READ;
            end
         end 
         end
         WAIT_READ: begin
         if(rd_shi_ack) begin
            if(rd_shi_addr == 
               ({(SRAM_ADDR_WIDTH){1'b1}}-1)) begin
               state_next = SRAM_WRITE;
               reqs_next = 0;
            end else begin
               rd_shi_addr_next = rd_shi_addr + 1;
               if(reqs == NUM_REQS) begin
                  state_next = SRAM_WRITE;
                  reqs_next = 0;
               end else begin
                  state_next = SRAM_READ;
                  reqs_next = reqs + 1;
               end
            end
	 		end 
	 		end //SRAM_READ
	 		SRAM_WRITE: begin
	 		if(in_fifo_shift_empty) 
            state_next = SRAM_READ;
         else begin
            wr_shi_req_next = 1;
            wr_shi_data_next = in_fifo_shift_dout;
            in_fifo_shift_rd_en = 1;
            state_next = WAIT_WRITE;
         end
         end //SRAM_WRITE
         WAIT_WRITE: begin
         if(wr_shi_ack)   
            state_next = SRAM_WRITE;
            wr_shi_addr_next = wr_shi_addr + 1;
	 		end 
         WAIT_WATCHDOG: begin
         if(watchdog_signal) begin
            state_next = SRAM_READ;
            rd_shi_addr_next = 0;
            wr_shi_addr_next = 0;
         end
         end
         default: $stop;
	 	endcase
	 end
	 
	 always @(posedge clk) begin
	 	if (reset) begin
	 		state <= SRAM_READ;
         wr_shi_data <= 0;
	 	   {rd_shi_req,wr_shi_req} <= 2'b0;
         {rd_shi_addr,wr_shi_addr} <= 0;
         reqs <= 0;
	 	end else begin
         if(watchdog_signal) begin
            state <= SRAM_READ;
            {rd_shi_req,wr_shi_req} <= 2'b0;
            {rd_shi_addr,wr_shi_addr} <= 0;
            wr_shi_data <= 0;
            reqs <= 0;
         end else begin
            state <= state_next;
            wr_shi_data <= wr_shi_data_next;
            rd_shi_req <= rd_shi_req_next;
            wr_shi_req <= wr_shi_req_next;
            rd_shi_addr <= rd_shi_addr_next;
            wr_shi_addr <= wr_shi_addr_next;
            reqs <= reqs_next;
         end
      end	
	 end //always @(posedge clk)

endmodule
