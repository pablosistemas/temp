`timescale  1ns /  10ps

module bloom_filter
   #(
      parameter DATA_WIDTH = 64,
      parameter CTRL_WIDTH = DATA_WIDTH/8,
      parameter SRAM_ADDR_WIDTH = 19,
      parameter SRAM_DATA_WIDTH = 72,
      parameter BITSBUCKET    = 4, 
      parameter NUM_BUCKETS  = 12,
      parameter INDEX_LEN = NUM_BUCKETS*BITSBUCKET,
      parameter UDP_REG_SRC_WIDTH = 2
   ) (

      input                               	is_ack,
      input    [SRAM_ADDR_WIDTH-1:0]      	index_0,
      input    [SRAM_ADDR_WIDTH-1:0]      	index_1,
		output											in_rdy,
		input												in_wr,

      /* interface to SRAM */
      output reg                          	wr_req,
      output reg [SRAM_ADDR_WIDTH-1:0]    	wr_addr,
      output reg [SRAM_DATA_WIDTH-1:0]    	wr_data,
      input                               	wr_ack,

      output reg                          	rd_req,
      output reg [SRAM_ADDR_WIDTH-1:0]    	rd_addr,
      input [SRAM_DATA_WIDTH-1:0]         	rd_data,
      input                               	rd_ack,
      input                               	rd_vld,

      output                           	   wr_shi_req,
      output [SRAM_ADDR_WIDTH-1:0]    	      wr_shi_addr,
      output [SRAM_DATA_WIDTH-1:0]    	      wr_shi_data,
      input                               	wr_shi_ack,

      output                               	rd_shi_req,
      output [SRAM_ADDR_WIDTH-1:0]        	rd_shi_addr,
      input [SRAM_DATA_WIDTH-1:0]         	rd_shi_data,
      input                               	rd_shi_ack,
      input                               	rd_shi_vld,

      // misc
      input                                	reset,
      input                                	clk
   );

   /* ----------Estados----------*/

	localparam SRAM_READ = 1;
	localparam SRAM_WRITE = 2;
	
	localparam NUM_STATES = 2;

   localparam HASH_FIFO_DATA_WIDTH = 1 + 2*SRAM_ADDR_WIDTH;
   localparam SRAM_FIFO_DATA_WIDTH = SRAM_DATA_WIDTH;

   // Define the log2 function
   `LOG2_FUNC

   /* interface to fifo hash */
   wire                    					in_fifo_hash_empty;
   reg                     					in_fifo_hash_rd_en;
   wire [HASH_FIFO_DATA_WIDTH-1:0]        in_fifo_hash_dout;
   wire                    					in_fifo_hash_wr;
   wire      						            in_fifo_hash_full;
      
   /* interface to SRAM fifo */
   reg                     					in_fifo_shift_rd_en;
   wire                    					in_fifo_shift_empty;
   wire [SRAM_DATA_WIDTH-1:0]    			in_fifo_shift_dout;
   wire                    					in_fifo_shift_wr;
   wire                    					in_fifo_shift_full;   

   /* interface to SRAM */
   reg [SRAM_DATA_WIDTH-1:0]					wr_data_next;
   reg [SRAM_ADDR_WIDTH-1:0]					wr_addr_next;
	reg												wr_req_next;
   reg [SRAM_ADDR_WIDTH-1:0]					rd_addr_next;
	reg												rd_req_next;

	wire [NUM_BUCKETS-1:0]   					indice;

	reg [NUM_STATES-1:0]							state, state_next;

   reg [SRAM_DATA_WIDTH-1:0]              temp_data;

   wire                                   update_bucket;
	
	/* ----------- local assignments -----------*/
	/* hash FIFO */
   assign in_rdy = !in_fifo_hash_full;
	assign in_fifo_hash_wr = in_wr;
   /* SRAM FIFO */
   assign in_fifo_shift_wr = rd_vld;

	/* --------------instances of external modules------------------ */
	
   /* fifo holds reqs and addr from write in BF */
   /* fifo in: {req_data,req_ack,hash1,hash2} */
   fallthrough_small_fifo #(
         .WIDTH(HASH_FIFO_DATA_WIDTH), 
         .MAX_DEPTH_BITS(3)) in_fifo_hash 
        (.din ({is_ack,index_0,index_1}),// in
         .wr_en (in_fifo_hash_wr), // Write enable
         .rd_en (in_fifo_hash_rd_en), // Read the next word 
         .dout ({in_fifo_hash_dout}),
         .full (in_fifo_hash_full),
         .nearly_full (),
         .empty (in_fifo_hash_empty),
         .reset (reset),
         .clk (clk));

   lookup_bucket 
     #(
        .INPUT_WIDTH(SRAM_DATA_WIDTH),	
        .OUTPUT_WIDTH(NUM_BUCKETS)) busca_bucket
   	(
   		.data	(temp_data),
   		.index ({indice}));

	/* fires an updating signal when reached time to shift 
   * the current bucket */   	 
   watchdog
     #(.TIMER_LIMIT  (50)) watchdog
   	(
   		.update      (update_bucket),
    // --- Misc
    		.clk            (clk),
    		.reset          (reset));
	 
   shifter #(
      .SRAM_ADDR_WIDTH (SRAM_ADDR_WIDTH),
      .SRAM_DATA_WIDTH (SRAM_DATA_WIDTH),
      .NUM_REQS (5),
      .ADDR_SHIFT (2**SRAM_ADDR_WIDTH)
   ) SRAM_shifter (

      .wr_shi_req    (wr_shi_req),
      .wr_shi_addr   (wr_shi_addr),
      .wr_shi_data   (wr_shi_data),
      .wr_shi_ack    (wr_shi_ack),

      .rd_shi_req    (rd_shi_req),
      .rd_shi_addr   (rd_shi_addr),
      .rd_shi_data   (rd_shi_data),
      .rd_shi_ack    (rd_shi_ack),
      .rd_shi_vld    (rd_shi_vld),

      .watchdog_signal (update_bucket),

      .reset (reset),
      .clk (clk)
   );

   /* This state machine only does shifts in memory.
   *  We have installed two parallel bus in SRAM and
   *  the arbiter module choices with priority criteria
   *  defined in it. */
	 always @(*) begin
	 	/* FIFOS */
	 	in_fifo_hash_rd_en = 0;
	 	/* SRAM */
	 	{rd_req_next, wr_req_next} = 2'b0;
	 	{rd_addr_next, wr_addr_next} = {rd_addr, wr_addr};
	 	wr_data_next = wr_data;
	 	
      state_next = state;

	 	case(state)
	 		SRAM_READ: begin
	 		if(!in_fifo_hash_empty) begin
	 			in_fifo_hash_rd_en = 1;	
	 		end
	 		end //SRAM_READ
	 		SRAM_WRITE: begin
	 		if(!in_fifo_hash_empty) begin
	 					
	 		end
	 		end //SRAM_WRITE
	 	endcase
	 end
	 
	 always @(posedge clk) begin
	 	if (reset) begin
	 		state <= SRAM_READ;
         wr_data <= 0;
	 	   {rd_req,wr_req} <= 2'b0;
         {rd_addr,wr_addr} <= 0;
	 	end else begin
	 		state <= state_next;
         wr_data <= wr_data_next;
	 	   {rd_req,wr_req} <= {rd_req_next,wr_req_next};
         {rd_addr,wr_addr} <= {rd_addr_next,wr_addr_next};
      end	
	 end //always @(posedge clk)

   /* DEBUG */
   //synthesis translate_off
   always @(posedge clk) begin
      if(in_fifo_hash_full) begin
         $display("FIFO HASH FULL\n");
         $stop;
      end
      if(!in_fifo_hash_empty) begin
         $display("HASH FIFO: %x %x\n",
   in_fifo_hash_dout[2*SRAM_ADDR_WIDTH-1:SRAM_ADDR_WIDTH],
         in_fifo_hash_dout[SRAM_ADDR_WIDTH-1:0]);
      end
   end
   //synthesis translate_on
    
endmodule
