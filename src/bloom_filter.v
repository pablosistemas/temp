`timescale  1ns /  10ps

module bloom_filter
   #(
      parameter DATA_WIDTH =64,
      parameter CTRL_WIDTH =DATA_WIDTH/8,
      parameter SRAM_ADDR_WIDTH =19,
      parameter SRAM_DATA_WIDTH =72,
      parameter NUM_BITS_BUCKET =4, 
      parameter RESERVED =16,
      parameter NUM_BUCKETS =(SRAM_DATA_WIDTH-RESERVED)/NUM_BITS_BUCKET,
      parameter UDP_REG_SRC_WIDTH = 2
   ) (

      input                               	is_ack,
      input    [SRAM_ADDR_WIDTH-1:0]      	index_0,
      input    [SRAM_ADDR_WIDTH-1:0]      	index_1,
      input [95:0]                           tuple,
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

      input                                  enable,

   /* interface to MED fifo */
      output reg [WORD_WIDTH-1:0]    			in_fifo_med_din,
      output reg                     			in_fifo_med_wr,
      input                    					in_fifo_med_full,

      // misc
      input                                	reset,
      input                                	clk
   );

   /* ----------Estados----------*/

	localparam ADDR1 =1;
	localparam ADDR2 =2;
   localparam WAIT_ADDR1 =4;
   localparam WAIT_ADDR2 =8;
   localparam WRITE_ADDR1 =16;
   localparam WRITE_ADDR2 =32;
   localparam WAIT_WR_ADDR1 =64;
   localparam WAIT_WR_ADDR2 =128;
   localparam PAYLOAD1 =256;
   localparam PAYLOAD2 =512;
	
	localparam NUM_STATES = 10;

   localparam TUPLE_WIDTH =96;

   localparam HASH_FIFO_DATA_WIDTH = 1+2*SRAM_ADDR_WIDTH+TUPLE_WIDTH;
   localparam SRAM_FIFO_DATA_WIDTH = SRAM_DATA_WIDTH;

   localparam BLOOM_POS = 16; //num bits reserved
   localparam BITS_SHIFT = log2(NUM_BUCKETS);

   localparam CLK = 8*10**-9;
   localparam TIMER = 50;

   // Define the log2 function
   `LOG2_FUNC

   /* interface to fifo hash */
   wire                    					in_fifo_hash_empty;
   reg                     					in_fifo_hash_rd_en;
   wire [HASH_FIFO_DATA_WIDTH-1:0]        in_fifo_hash_dout;
   wire                    					in_fifo_hash_wr;
   wire      						            in_fifo_hash_full;
   wire                                   hash_is_ack;
      
   /* interface to SRAM fifo */
   reg                     					in_fifo_sram_rd_en;
   wire                    					in_fifo_sram_empty;
   wire [SRAM_DATA_WIDTH-1:0]    			in_fifo_sram_dout;
   wire                    					in_fifo_sram_wr;
   wire                    					in_fifo_sram_full;



   /* interface to SRAM */
   reg [SRAM_DATA_WIDTH-1:0]					wr_data_next;
   reg [SRAM_ADDR_WIDTH-1:0]					wr_addr_next;
	reg												wr_req_next;
   reg [SRAM_ADDR_WIDTH-1:0]					rd_addr_next;
	reg												rd_req_next;

	wire [NUM_BUCKETS-1:0]   					indice;

	reg [NUM_STATES-1:0]							state, state_next;

   wire                                   watchdog;

   wire [SRAM_ADDR_WIDTH-1:0]             addr1, addr2;
   wire [SRAM_ADDR_WIDTH-1:0]             low_addr, high_addr;
   wire [SRAM_ADDR_WIDTH-1:0]             last_addr;
   wire [SRAM_DATA_WIDTH-1:0]             updated_data;
   wire [SRAM_DATA_WIDTH-1:0]             dado_deslocado;
   wire [SRAM_DATA_WIDTH-1:0]             updated_ack;

   reg [BITS_SHIFT-1:0]                   cur_bucket;
   reg [BLOOM_POS-BITS_SHIFT-1:0]         cur_loop;
	
	/* ----------- local assignments -----------*/
	/* hash FIFO */
   assign in_rdy = !in_fifo_hash_full;
	assign in_fifo_hash_wr = in_wr;

   /* SRAM FIFO */
   assign in_fifo_sram_wr = rd_vld;

   assign hash_is_ack = in_fifo_hash_dout[HASH_FIFO_DATA_WIDTH-1];
   assign addr1 = in_fifo_hash_dout[SRAM_ADDR_WIDTH-1:0];
   assign addr2 = in_fifo_hash_dout[2*SRAM_ADDR_WIDTH-1:SRAM_ADDR_WIDTH];
   assign tuple_ptr = in_fifo_hash_dout[HASH_FIFO_DATA_WIDTH-2:HASH_FIFO_DATA_WIDTH-1-TUPLE_WIDTH];
   
   assign low_addr = addr1 < addr2?addr1:addr2;
   assign high_addr = addr1 >= addr2?addr1:addr2;

   /* updates the data that will be used if hash was calculated
      * over data packet */
   assign updated_data = dado_deslocado+{{(NUM_BITS_BUCKET-1){1'b0}},1'b1,{(SRAM_DATA_WIDTH-NUM_BITS_BUCKET){1'b0}}};
  
   /* updates the data that will be used if hash was calculated
      * over ack packet */
   generate
      genvar i;
      for(i=0;i < NUM_BUCKETS;i=i+1) begin: updt_bloom_ack
         assign updated_ack[BLOOM_POS+(i+1)*NUM_BITS_BUCKET-1:BLOOM_POS+i*NUM_BITS_BUCKET] = dado_deslocado[BLOOM_POS+(i+1)*NUM_BITS_BUCKET-1:BLOOM_POS+i*NUM_BITS_BUCKET]-indice[i];
      end
   endgenerate

   /* evaluates buckets-diff by index */
   wire [BITS_SHIFT-1:0]   latencia;
   wire [31:0]             medicao;
   reg [BITS_SHIFT-1:0]    medicao1, medicao1_next;
   reg [BITS_SHIFT-1:0]    medicao2, medicao2_next;

   generate
   genvar j;
      assign latencia = 0;
      for(j=0;j<NUM_BUCKETS;j=j+1) begin: latencia_mod
         assign latencia = indice[j]?j:0;
      end
   endgenerate

   /* if medicao1 differs from medicao2 means false positive */
   assign medicao = medicao1==medicao2?medicao1:0;


   /* builds the packet word with latency measured */
   localparam WORD_WIDTH = DATA_WIDTH; //96+BITS_SHIFT; // 2*IP+2*PORTA+latencia

/* --------------instances of external modules-------------- */
   /* fifo holds reqs and addr from write in BF */
   /* fifo in: {req_data,req_ack,hash1,hash2} */
   fallthrough_small_fifo_old #(
         .WIDTH(HASH_FIFO_DATA_WIDTH), 
         .MAX_DEPTH_BITS(3)) in_fifo_hash 
        (.din        ({is_ack,tuple,index_0,index_1}),// in
         .wr_en      (in_fifo_hash_wr), // Write enable
         .rd_en      (in_fifo_hash_rd_en),// Read the next word
         .dout       ({in_fifo_hash_dout}),
         .full       (in_fifo_hash_full),
         .nearly_full(),
         .empty      (in_fifo_hash_empty),
         .reset      (reset),
         .clk        (clk));

   /* data came from SRAM */
   fallthrough_small_fifo_old #(
         .WIDTH(SRAM_DATA_WIDTH), 
         .MAX_DEPTH_BITS(3)) in_fifo_sram
        (.din        (rd_data),// in
         .wr_en      (in_fifo_sram_wr), // Write enable
         .rd_en      (in_fifo_sram_rd_en),// Read the next word
         .dout       (in_fifo_sram_dout),
         .full       (in_fifo_sram_full),
         .nearly_full(),
         .empty      (in_fifo_sram_empty),
         .reset      (reset),
         .clk        (clk));

   /* look up the most recently updated bucket */   
   lookup_bucket 
     #(
      .INPUT_WIDTH(SRAM_DATA_WIDTH),	
      .OUTPUT_WIDTH(NUM_BUCKETS),
      .BUCKET_SZ(NUM_BITS_BUCKET),
      .NUM_BUCKETS(NUM_BUCKETS)      
     ) busca_bucket (
   		.data	(dado_deslocado),
   		.index (indice));
  
      /* updates data that came from SRAM */
   atualiza_linha #(
   		.DATA_WIDTH(SRAM_DATA_WIDTH), 
   		.NUM_BUCKETS(NUM_BUCKETS),
         .BUCKET_SZ(NUM_BITS_BUCKET),
         .BLOOM_INIT_POS(BLOOM_POS)
      ) atualiza_bucket_shift (
         .data (in_fifo_sram_dout), 
         .output_data (dado_deslocado), 
         .cur_bucket (cur_bucket), 
         .cur_loop (cur_loop));
 
   /* fires an updating signal when reached time to shift 
    * the current bucket */   	 
   watchdog
     #(.TIMER_LIMIT  (TIMER)) watchdog_module
   	(
   		.update      (watchdog),
    // --- Misc
         .enable        (enable),
    		.clk           (clk),
    		.reset         (reset));
	 
   shift_mark #(
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

      .enable        (enable),

      .watchdog_signal (watchdog),

      .cur_bucket    (cur_bucket),
      .cur_loop      (cur_loop),
      //.last_addr     (last_addr),

      .reset (reset),
      .clk (clk));

	 always @(*) begin
	 	/* FIFOS */
	 	in_fifo_hash_rd_en = 0;
      in_fifo_sram_rd_en = 0;
      in_fifo_med_wr =0;
      in_fifo_med_din =0;

	 	/* SRAM */
	 	{rd_req_next, wr_req_next} = 2'b0;
	 	{rd_addr_next, wr_addr_next} = {rd_addr, wr_addr};
	 	wr_data_next = wr_data;

      /* medicoes */
      medicao1_next = medicao1;
      medicao2_next = medicao2;
	 	
      state_next = state;

	 	case(state)
	 		ADDR1: begin
	 		if(!in_fifo_hash_empty) begin
            rd_addr_next = low_addr;
            rd_req_next = 1;
            state_next = WAIT_ADDR1;
	 		end
	 		end 
         WAIT_ADDR1: begin
            if(rd_ack)
               state_next = ADDR2;
            else rd_req_next = 1;
         end
         ADDR2: begin
            rd_addr_next = high_addr;
            rd_req_next = 1;
            state_next = WAIT_ADDR2;
	 		end
         WAIT_ADDR2: begin
            if(rd_ack)
               state_next = WRITE_ADDR1;
            else rd_req_next = 1;
         end
         WRITE_ADDR1: begin
            if (!in_fifo_sram_empty) begin
               wr_req_next = 1;
               wr_addr_next = low_addr;
               if(hash_is_ack)
                  wr_data_next = updated_ack;
               else
                  wr_data_next = updated_data;
               state_next = WAIT_WR_ADDR1;
            end
         end
         WAIT_WR_ADDR1: begin
            if(wr_ack) begin
               state_next = WRITE_ADDR2;
               medicao1_next = latencia;
               in_fifo_sram_rd_en = 1;
            end else 
               wr_req_next = 1;
         end
         WRITE_ADDR2: begin
            wr_req_next = 1;
            wr_addr_next = low_addr;
            if(hash_is_ack)
               wr_data_next = updated_ack;
            else
               wr_data_next = updated_data;
            state_next = WAIT_WR_ADDR2;
         end
         WAIT_WR_ADDR2: begin
            if(wr_ack) begin
               state_next = PAYLOAD1; //ADDR1;
               medicao2_next = latencia;
               in_fifo_sram_rd_en = 1;
            end else 
               wr_req_next = 1;
         end
         PAYLOAD1: begin
            /* write in fifo the word with results */
            if(!in_fifo_med_full) begin //if fifo full, discard
               in_fifo_med_din = tuple[95:32]; //ip1 e ip2
               in_fifo_med_wr =1;
               state_next = ADDR1;
            end else
               state_next = PAYLOAD2;
         end
         PAYLOAD2: begin
            in_fifo_med_din = {tuple[31:0],medicao};
            in_fifo_med_wr =1;
            state_next = ADDR1;
            /* catch next tuple */
            in_fifo_hash_rd_en = 1;
         end
         default: begin
            $display("DEFAULT BLOOM FILTER\n");
            $stop;
         end
	 	endcase
	 end
	 
	 always @(posedge clk) begin
	 	if (reset) begin
	 		state <= ADDR1;
         wr_data <= 0;
	 	   {rd_req,wr_req} <= 2'b0;
         {rd_addr,wr_addr} <= 0;
         {medicao1,medicao2} <=0;
	 	end else begin
         if(watchdog) begin
            /* updates bloom filter counter */
            cur_bucket <= cur_bucket+'h1;
            if(cur_bucket == {BITS_SHIFT{1'b1}})
               cur_loop <= cur_loop + 'h1;
         end 
         else begin
            state <= state_next;
            wr_data <= wr_data_next;
            {rd_req,wr_req} <= {rd_req_next,wr_req_next};
            {rd_addr,wr_addr} <= {rd_addr_next,wr_addr_next};
            medicao1 <=medicao1_next;
            medicao2 <=medicao2_next;
         end
      end	
	 end //always @(posedge clk)

   /* DEBUG */
   //synthesis translate_off
   always @(posedge clk) begin
      if(state_next == WAIT_ADDR1)
         $display("WAIT_ADDR1\n");
      if(state_next == WAIT_ADDR2)
         $display("WAIT_ADDR2\n");
      if(rd_ack)
         $display("RECV ACK\n");
      if(in_fifo_hash_full) begin
         $display("FIFO HASH FULL\n");
         $stop;
      end
      if(state_next == ADDR1 && !in_fifo_hash_empty) begin
         $display("HASH FIFO: %x %x\n",addr1,addr2);
      end
   end
   //synthesis translate_on
    
endmodule

/*
*	 always @(*) begin
	 	in_fifo_hash_rd_en = 0;
	 	{rd_req_next, wr_req_next} = 2'b0;
	 	{rd_addr_next, wr_addr_next} = {rd_addr, wr_addr};
	 	wr_data_next = wr_data;
	 	
      state_next = state;

	 	case(state)
	 		ADDR1: begin
	 		if(!in_fifo_hash_empty) begin
            if(low_addr <= last_addr) begin
               rd_addr_next = low_addr;
               rd_req_next = 1;
               state_next = WAIT_ADDR1;
            end
	 		end
	 		end 
         WAIT_ADDR1: begin
            if(rd_ack)
               state_next = ADDR2;
            else rd_req_next = 1;
         end
         ADDR2: begin
            if(high_addr <= last_addr) begin
               rd_addr_next = high_addr;
               rd_req_next = 1;
               state_next = WAIT_ADDR2;
            end
	 		end
         WAIT_ADDR2: begin
            if(rd_ack)
               state_next = WRITE_ADDR1;
            else rd_req_next = 1;
         end
         WRITE_ADDR1: begin
            if (!in_fifo_sram_empty) begin
               if(hash_is_ack)
                  wr_data_next = updated_ack;
               else
                  wr_data_next = updated_data;
               in_fifo_hash_rd_en = 1;
               state_next = WAIT_WR_ADDR1;
            end
         end
         WAIT_WR_ADDR1: begin
            if(wr_ack)
               state_next = WRITE_ADDR2;
            else 
               wr_req_next = 1;
         end
         WRITE_ADDR2: begin
            state_next = 
         end
         default: begin
            $display("DEFAULT BLOOM FILTER\n");
            $stop;
         end
	 	endcase
	 end */
