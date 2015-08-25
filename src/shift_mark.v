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

module shift_mark
   #(
      parameter SRAM_ADDR_WIDTH = 19,
      parameter SRAM_DATA_WIDTH = 72,
      parameter NUM_REQS = 5,
      parameter SHIFT_WIDTH = SRAM_ADDR_WIDTH,
      parameter NUM_BITS_BUCKET = 4,
      parameter NUM_BITS_RESERVED = 16,
      parameter NUM_BUCKETS = (SRAM_DATA_WIDTH-NUM_BITS_RESERVED)/NUM_BITS_BUCKET
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

      input                                  enable,

      /* watchdog */ 
      input                                  watchdog_signal,

      /* shifts ctrl */
      input [BITS_SHIFT-1:0]                 cur_bucket,
      input [BLOOM_POS-BITS_SHIFT-1:0]       cur_loop,
   
      /* Bloom filter: last addr updated in SRAM */   
      //output reg [SRAM_ADDR_WIDTH-1:0]       last_addr,

      // misc
      input                                	reset,
      input                                	clk
   );

   // Define the log2 function
   `LOG2_FUNC

   /* ----------Estados----------*/

	localparam SRAM_READ = 1;
	localparam SRAM_WRITE = 2;
   localparam WAIT_WATCHDOG = 4;
   localparam WAIT_READ = 8;
   localparam WAIT_WRITE =16;
	
	localparam NUM_STATES = 5;
   localparam NUM_BITS_REQS = log2(NUM_REQS);

   localparam HASH_FIFO_DATA_WIDTH = 1 + 2*SRAM_ADDR_WIDTH;
   
   localparam BLOOM_POS =NUM_BITS_RESERVED;
   localparam BITS_SHIFT = log2(NUM_BUCKETS);

   localparam ADDR_BOUND ={{(SRAM_ADDR_WIDTH-SHIFT_WIDTH){1'b0}},{SHIFT_WIDTH{1'b1}}};


   /* interface to SRAM */
   reg [SRAM_DATA_WIDTH-1:0]					wr_shi_data_next;
   //reg [SRAM_ADDR_WIDTH-1:0]					wr_shi_addr_next;
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
   wire [SRAM_DATA_WIDTH-1:0]             in_fifo_shift_dout;
   wire [SRAM_DATA_WIDTH-1:0]             shift_dout;

   // persistency
   reg                                    delay, delay_next;

   // watchdog
   reg                  watchdog_fired, watchdog_fired_next;

   //bucket and loop
   reg [BITS_SHIFT-1:0]                 bucket, bucket_next,
                                          nxt_bucket;
   reg [BLOOM_POS-BITS_SHIFT-1:0]       loop, loop_next,
                                          nxt_loop;
   
	/* ----------- local assignments -----------*/
   
   assign in_fifo_shift_wr = rd_shi_vld && !in_fifo_shift_full;
   /* data shifted 
   *  [71:BLOOM_POS] data
   *  [BLOOM_POS-1:0] control: last bucket */

	/* --------------instances of external modules------------------ */
	
   /* fifo holds data read from sram */
   fallthrough_small_fifo_old #(
   		.WIDTH(SRAM_DATA_WIDTH), 
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

   /* fifo holds next addr to write */
   wire [SRAM_ADDR_WIDTH-1:0]                next_addr_dout;
   reg                                       next_addr_rd_en;
   reg                                       next_addr_wr;

   fallthrough_small_fifo_old #(
   		.WIDTH(SRAM_ADDR_WIDTH), 
   		.MAX_DEPTH_BITS(3)) fifo_next_addr_write 
        (.din ({rd_shi_addr}), // Data in
         .wr_en (next_addr_wr), // Write enable
         .rd_en (next_addr_rd_en), // Read the next word 
         .dout ({next_addr_dout}),
         .full (next_addr_full),
         .nearly_full (),
         .empty (next_addr_empty),
         .reset (reset),
         .clk (clk));


      /* DEBUG */
      // synthesis translate_off
   wire [SRAM_ADDR_WIDTH-1:0]                sram_addr;
   wire [SRAM_ADDR_WIDTH-1:0]                sram_addr_dout;
   reg                                       sram_fifo_rd_en;
   reg                                       sram_fifo_wr_en;

   assign sram_addr = rd_shi_addr;

   fallthrough_small_fifo_old #(
   		.WIDTH(SRAM_ADDR_WIDTH), 
   		.MAX_DEPTH_BITS(3)) sram_shift
        (.din (sram_addr), // Data in
         .wr_en (sram_fifo_wr_en), // Write enable
         .rd_en (sram_fifo_rd_en), // Read the next word 
         .dout ({sram_addr_dout}),
         .full (sram_addr_full),
         .nearly_full (),
         .empty (sram_addr_empty),
         .reset (reset),
         .clk (clk));


   wire [SRAM_ADDR_WIDTH-1:0]                wr_addr_dout;
   reg                                       wr_fifo_rd_en;

   fallthrough_small_fifo_old #(
   		.WIDTH(SRAM_ADDR_WIDTH), 
   		.MAX_DEPTH_BITS(3)) sram_shift_addr_wr
        (.din (sram_addr), // Data in
         .wr_en (sram_fifo_wr_en), // Write enable
         .rd_en (wr_fifo_rd_en), // Read the next word 
         .dout ({wr_addr_dout}),
         .full (wr_addr_full),
         .nearly_full (),
         .empty (wr_addr_empty),
         .reset (reset),
         .clk (clk));

   wire [SRAM_DATA_WIDTH-1:0]                wr_data_dout;
   reg                                       wr_data_wr_en;
   reg                                       wr_data_rd_en;

   fallthrough_small_fifo_old #(
   		.WIDTH(SRAM_DATA_WIDTH), 
   		.MAX_DEPTH_BITS(3)) sram_shift_data_wr
        (.din (shift_dout), // Data in
         .wr_en (wr_data_wr_en), // Write enable
         .rd_en (wr_data_rd_en), // Read the next word 
         .dout ({wr_data_dout}),
         .full (wr_data_full),
         .nearly_full (),
         .empty (wr_data_empty),
         .reset (reset),
         .clk (clk));
      // synthesis translate_on

   /* updates data that came from SRAM */
   atualiza_linha #(
   		.DATA_WIDTH(SRAM_DATA_WIDTH), 
   		.NUM_BUCKETS(NUM_BUCKETS),
         .BUCKET_SZ(NUM_BITS_BUCKET),
         .BLOOM_INIT_POS(BLOOM_POS)
      ) atualiza_bucket_shift 
        (.data (in_fifo_shift_dout), 
         .output_data (shift_dout), 
         .cur_bucket (bucket),//cur_bucket), 
         .cur_loop (loop));//cur_loop));

   /*  */
	 always @(*) begin
      in_fifo_shift_rd_en = 0; 
      next_addr_rd_en = 0;
      next_addr_wr = 0;

	 	/* SRAM */
	 	{rd_shi_req_next, wr_shi_req_next} = 2'b0;
	 	rd_shi_addr_next = rd_shi_addr;
      //wr_shi_addr_next = wr_shi_addr;
	 	
      //synthesis translate_off
      sram_fifo_wr_en = 0;
      wr_data_wr_en = 0;
      //synthesis translate_on

      state_next = state;
      reqs_next = reqs;

      /* watchdog */
      watchdog_fired_next = watchdog_fired;

      //persistency
      delay_next = delay;

      //bucket and loop
      bucket_next = bucket;
      loop_next = loop;

	 	case(state)
	 		SRAM_READ: begin
	 		if(!in_fifo_shift_full && enable) begin
            if(rd_shi_addr == ADDR_BOUND-1)
               state_next = WAIT_WATCHDOG;
            else begin
               rd_shi_req_next = 1;
               state_next = WAIT_READ;

               // persistency
               delay_next = 0;
            end
         end 
         //else $stop; //remove this line 
         end
         WAIT_READ: begin
         // persistency   
         if(!rd_shi_ack && delay == 0)
            delay_next = 1;
         else if(!rd_shi_ack && delay) begin
            delay_next = 0;  
            rd_shi_req_next = 1;
         end

         if(rd_shi_ack) begin
            $display("READ ack\n");
            if(rd_shi_addr == ADDR_BOUND-1) begin
               state_next = SRAM_WRITE;
               reqs_next = 0;
            end 
            else begin
               rd_shi_addr_next = rd_shi_addr + 1;
               if(reqs == NUM_REQS) begin
                  state_next = SRAM_WRITE;
                  reqs_next = 0;
               end else begin
                  state_next = SRAM_READ;
                  reqs_next = reqs + 1;
               end
            end
            //synthesis translate_off
            sram_fifo_wr_en = 1;
            //synthesis translate_on
            next_addr_wr = 1;
	 		end 
	 		end //SRAM_READ
	 		SRAM_WRITE: begin
	 		if(in_fifo_shift_empty) 
            state_next = SRAM_READ;
         else begin
            wr_shi_req_next = 1;
            state_next = WAIT_WRITE;
            //synthesis translate_off
            wr_data_wr_en = 1;
            //synthesis translate_on
            
            // persistency
            delay_next = 0;
         end
         end //SRAM_WRITE
         WAIT_WRITE: begin
         // persistency   
         if(!wr_shi_ack && delay == 0)
            delay_next = 1;
         else if(!wr_shi_ack && delay) begin
            delay_next = 0;  
            wr_shi_req_next = 1;
         end

         else if(wr_shi_ack) begin
            $display("WRITE ack\n");
            state_next = SRAM_WRITE;
            //wr_shi_addr_next = wr_shi_addr + 1;
            in_fifo_shift_rd_en = 1;
            next_addr_rd_en = 1;
         end
	 		end 
         WAIT_WATCHDOG: begin 
            if(watchdog_fired) begin
               state_next = SRAM_READ;
               watchdog_fired_next = 0;

               //bucket and loop
               bucket_next = nxt_bucket;
               loop_next = nxt_loop;

               rd_shi_addr <= {SRAM_ADDR_WIDTH{1'b0}};
            end
         end //do nothing
         default: begin
           $stop;
         end
	 	endcase
	 end
	 
	 always @(posedge clk) begin
	 	if (reset) begin
	 		state <= SRAM_READ;
         wr_shi_data <= 0;
	 	   {rd_shi_req,wr_shi_req} <= 2'b0;
         {rd_shi_addr,wr_shi_addr} <= 0;
         reqs <= 0;
         //last_addr <= 0; //last addr shifted
         
         // watchdog
         watchdog_fired <= 1'b0;

         // bucket and loop - cur and next
         bucket <= 0;
         loop <= 0;
         nxt_bucket <= 0;
         nxt_loop <= 0;

         // persistency
         delay <= 0;
	 	end else begin
         if(watchdog_signal) begin
            //state <= SRAM_READ;
            /*{rd_shi_req,wr_shi_req} <= 2'b0;
            {rd_shi_addr,wr_shi_addr} <= 0;
            wr_shi_data <= 0;
            reqs <= 0;*/

            rd_shi_addr <= {SRAM_ADDR_WIDTH{1'b0}};

            // watchdog
            watchdog_fired <= 1'b1;
         end 
         else begin
            rd_shi_addr <= rd_shi_addr_next;
            watchdog_fired <= watchdog_fired_next;
         end
         state <= state_next;
         wr_shi_data <= shift_dout; //wr_shi_data_next;
         rd_shi_req <= rd_shi_req_next;
         wr_shi_req <= wr_shi_req_next;
         wr_shi_addr <= next_addr_dout; //wr_shi_addr_next;
         reqs <= reqs_next;
            //last_addr <= wr_shi_addr;
            
         // persistency
         delay <= delay_next;

         //bucket and loop
         nxt_bucket <= cur_bucket;
         nxt_loop <= cur_loop;
         bucket <= bucket_next;
         loop <= loop_next;
      end	
	 end //always @(posedge clk)

    /* DEBUG */
    // synthesis translate_off
    always @(posedge clk) begin
       if(sram_addr_full)
          $stop;
      sram_fifo_rd_en <= 0;       
      wr_fifo_rd_en <= 0;       
      wr_data_rd_en <= 0;       
       if(rd_shi_req_next)  
          $display("reading addr: %x\n",rd_shi_addr_next);
       /*if(wr_shi_req_next)
          $display("updating addr: %x\n",wr_shi_addr_next);*/
       if(watchdog_signal)
          $display("WATCHDOG\n");
       if(rd_shi_vld) begin
         $display("dataread[%x]: %x\n",sram_addr_dout,rd_shi_data);
         sram_fifo_rd_en <= 1;       
       end
       if(wr_shi_ack) begin
         $display("datawrite[%x]: %x,%d,%d",wr_addr_dout,wr_data_dout,cur_bucket,cur_loop);
         wr_fifo_rd_en <= 1;       
         wr_data_rd_en <= 1;       
      end
      //if(state_next == WAIT_WATCHDOG)
      //   $display("WAIT_WATCHDOG\n");
    end
    // synthesis translate_on

endmodule
