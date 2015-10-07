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
      /* enable from sram arbiter */
      input                                  enable,

   /* interface to MED fifo */
      output reg [DATA_WIDTH-1:0]    			in_fifo_med_din,
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
   localparam NOP1 =1024;
   localparam NOP2 =2048;
   localparam REQ_SHIFT_STOP =4096;
	
	localparam NUM_STATES = 13;

   localparam TUPLE_WIDTH =96;

   localparam HASH_FIFO_DATA_WIDTH = 1+2*SRAM_ADDR_WIDTH+TUPLE_WIDTH;
   localparam SRAM_FIFO_DATA_WIDTH = SRAM_DATA_WIDTH;

   localparam BLOOM_POS = 16; //num bits reserved
   localparam BITS_SHIFT = log2(NUM_BUCKETS);

   localparam TIMER = 2**10; //2875000; //2875000 perbucket~=320ms total

   // Define the log2 function
   `LOG2_FUNC
   
   /* implements persistence in reqs because SRAM is shared
   with some others modules 
   
   -> decides the next states and set the signals */
   
	task read_persistence;
		input			is_ack;
		input			_delay;
		output		delay_next;
		/* reqs */
		output		_req;
		/* decides next _state */
		output [NUM_STATES-1:0]	_state;
		input	[NUM_STATES-1:0]	_current;
		input	[NUM_STATES-1:0]	_next;
		begin
			$display("Task inputs: %d %d %d %d\n",is_ack,_delay,_current,_next);
		
			if(!is_ack && _delay == 0) begin
				delay_next = 1;
				_req = 0;
				_state = _current;
			end
			else if(!is_ack && _delay) begin
				delay_next = 0;  
				_req = 1;
				_state = _current;
			end
			else if(is_ack) begin
				_state = _next;
				delay_next = 0;
				_req = 0;
			end
			/* when is_ack is x. write_persistence dont need that because ack is 
			initialized when these _state is reached */
			else begin
				_state = _current;
				if(_delay) _req = 1;
				else _req = 0;
				delay_next = ~_delay;
			end
		end
	endtask 

   task write_persistence;
		input							is_ack;
		input							_delay;
		output						delay_next;
		/* reqs */
		output						_req;
		/* decides next state */
		output [NUM_STATES-1:0]	state;
		input	[NUM_STATES-1:0]	_current;
		input	[NUM_STATES-1:0]	_next;
		
		output						fifo_rd_en;
		
		begin
         _req = 0;
			if(!is_ack) begin
				if(_delay == 0) begin
					delay_next = 1;
				end
				else begin
					delay_next = 0;
					_req = 1;	
				end
				state = _current;
				fifo_rd_en = 0;
			end
         else if(is_ack) begin
   	      state = _next;
            fifo_rd_en = 1;
         end
         else
            $stop;
		end	   
   endtask

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
   reg [SRAM_ADDR_WIDTH-1:0]					rd_addr_next;
	reg												wr_req_next;
	reg												rd_req_next;

	wire [NUM_BUCKETS-1:0]   					indice;

	reg [NUM_STATES-1:0]							state, state_next;

   wire                                   watchdog;

   wire [SRAM_ADDR_WIDTH-1:0]             addr1, addr2;
   wire [SRAM_ADDR_WIDTH-1:0]             low_addr, high_addr;
   //wire [SRAM_ADDR_WIDTH-1:0]             last_addr;
   wire [SRAM_DATA_WIDTH-1:0]             updated_data;
   wire [SRAM_DATA_WIDTH-1:0]             dado_deslocado;
   wire [SRAM_DATA_WIDTH-1:0]             updated_ack;

   reg [BITS_SHIFT-1:0]                   cur_bucket;
   reg [BLOOM_POS-BITS_SHIFT-1:0]         cur_loop;
   
   // referem-se ao bucket e loop iniciais da pesquisa
   reg [BITS_SHIFT-1:0]                   _bucket,_bucket_nxt;
   reg [BLOOM_POS-BITS_SHIFT-1:0]         _loop,_loop_nxt;

   // read_persistence
   reg                                    delay, delay_next;
	
   reg [SRAM_DATA_WIDTH-1:0]              data_aft_shft;

   reg                                bloom_filter_disable_nxt;

   reg                                bloom_filter_disable;

	/* ----------- local assignments -----------*/
	/* hash FIFO */
   assign in_rdy = !in_fifo_hash_full;
	assign in_fifo_hash_wr = in_wr;

   /* SRAM FIFO */
   assign in_fifo_sram_wr = rd_vld;

   assign hash_is_ack = in_fifo_hash_dout[HASH_FIFO_DATA_WIDTH-1];
   assign addr1 = in_fifo_hash_dout[SRAM_ADDR_WIDTH-1:0];
   assign addr2 = in_fifo_hash_dout[2*SRAM_ADDR_WIDTH-1:SRAM_ADDR_WIDTH];
   //assign tuple_ptr = in_fifo_hash_dout[HASH_FIFO_DATA_WIDTH-2:HASH_FIFO_DATA_WIDTH-1-TUPLE_WIDTH];
   
   assign low_addr = addr1 < addr2?addr1:addr2;
   assign high_addr = addr1 >= addr2?addr1:addr2;

   /* updates the data that will be used if hash was calculated
      * over data packet */
   assign updated_data = dado_deslocado+{{(NUM_BITS_BUCKET-1){1'b0}},1'b1,{(SRAM_DATA_WIDTH-NUM_BITS_BUCKET){1'b0}}};
   //assign updated_data = dado_deslocado+{{(3*NUM_BITS_BUCKET-1){1'b0}},1'b1,{(SRAM_DATA_WIDTH-3*NUM_BITS_BUCKET){1'b0}}};
  
   /* updates the data that will be used if hash was calculated
      * over ack packet */
   generate
      genvar i;
      for(i=0;i < NUM_BUCKETS;i=i+1) begin: updt_bloom_ack
         assign updated_ack[BLOOM_POS+(i+1)*NUM_BITS_BUCKET-1:BLOOM_POS+i*NUM_BITS_BUCKET] = data_aft_shft[BLOOM_POS+(i+1)*NUM_BITS_BUCKET-1:BLOOM_POS+i*NUM_BITS_BUCKET]-indice[i];
      end
   endgenerate

   assign updated_ack[BLOOM_POS-1:0] =data_aft_shft[BLOOM_POS-1:0];

   /* evaluates buckets-diff by index */
   wire [BITS_SHIFT-1:0]   latencia;
   wire [31:0]             medicao;
   reg [BITS_SHIFT-1:0]    medicao1, medicao1_next;
   reg [BITS_SHIFT-1:0]    medicao2, medicao2_next;

   /*generate
   genvar j;
      assign latencia = 0;
      for(j=0;j<NUM_BUCKETS;j=j+1) begin: latencia_mod
         assign latencia = indice[j]?j:0;
      end
   endgenerate*/

/* --------------instances of external modules-------------- */
   /* fifo holds reqs and addr from write in BF */
   /* fifo in: {req_data,req_ack,hash1,hash2} */
   fallthrough_small_fifo_old #(
         .WIDTH(HASH_FIFO_DATA_WIDTH), 
         .MAX_DEPTH_BITS(3)) in_fifo_hash 
        (.din        ({is_ack,tuple,index_0,index_1}),// in
         .wr_en      (in_fifo_hash_wr), // Write enable
         .rd_en      (in_fifo_hash_rd_en),
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
   		.data	(data_aft_shft), //dado_deslocado),
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
         .cur_bucket (_bucket), 
         .cur_loop (_loop));
         //.cur_bucket (cur_bucket), 
         //.cur_loop (cur_loop));
       
   calcula_latencia #(
     .INDEX_WIDTH    (NUM_BUCKETS),
     .BITS_SHIFT     (BITS_SHIFT)) latencia_calc
     (
      .index      (indice),
      .latencia   (latencia));

   /* if medicao1 is diferent from medicao2 means false positive */
   assign medicao = medicao1==medicao2?medicao1:'hf;


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
	

   // wires for bloom filter protocol
   wire                 shift_disable;   

   shift_mark #(
      .SRAM_ADDR_WIDTH (SRAM_ADDR_WIDTH),
      .SRAM_DATA_WIDTH (SRAM_DATA_WIDTH),
      .NUM_REQS (5),
      .SHIFT_WIDTH (10)
   ) SRAM_shifter (

      .wr_shi_req       (wr_shi_req),
      .wr_shi_addr      (wr_shi_addr),
      .wr_shi_data      (wr_shi_data),
      .wr_shi_ack       (wr_shi_ack),

      .rd_shi_req       (rd_shi_req),
      .rd_shi_addr      (rd_shi_addr),
      .rd_shi_data      (rd_shi_data),
      .rd_shi_ack       (rd_shi_ack),
      .rd_shi_vld       (rd_shi_vld),

      .enable           (enable),

      .watchdog_signal  (watchdog),

      .cur_bucket       (cur_bucket),
      .cur_loop         (cur_loop),

      .bloom_filter_disable      (bloom_filter_disable),
      .shift_disable             (shift_disable),

      .reset            (reset),
      .clk              (clk));

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

      /* loop and bucket in search */
      _bucket_nxt = _bucket;
      _loop_nxt = _loop;
	 	
      state_next = state;

      //read_persistence
      delay_next = delay;

      // protocol to sram access between bloom filter and shift
      bloom_filter_disable_nxt = bloom_filter_disable;
      
	 	case(state)
         REQ_SHIFT_STOP: begin
            if(!in_fifo_hash_empty && enable) begin
               bloom_filter_disable_nxt = 1'b1;
               state_next = ADDR1;
            end
         end
	 		ADDR1: begin
	 		if(enable && !shift_disable) begin
            rd_addr_next = low_addr;
            rd_req_next = 1;
            state_next = WAIT_ADDR1;
   
            // read_persistence
            delay_next = 0;
	 		end
         else begin
            // current bucket and loop 
            _bucket_nxt =cur_bucket;
            _loop_nxt =cur_loop;
         end
	 		end 
	      WAIT_ADDR1: begin
		      $display("rd_ack: %b", rd_ack);			    
	      // decides the next state and sets the signals
		      read_persistence(rd_ack,delay,delay_next,rd_req_next,state_next,
		      					WAIT_ADDR1,ADDR2); 
		      $display("state_next: %d", state_next);
		      $display("req_next: %d", rd_req_next);			    
         end
         ADDR2: begin
            rd_addr_next = high_addr;
            $display("highaddr: %h|%h\n",high_addr,low_addr);
            rd_req_next = 1;
            state_next = WAIT_ADDR2;
            
            // read_persistence
            delay_next = 0;
	 		end
         WAIT_ADDR2: begin
         // decides the next state and sets the signals   
		      read_persistence(rd_ack,delay,delay_next,rd_req_next,state_next,
		      					WAIT_ADDR2,NOP1); //WRITE_ADDR1); 
		      $display("state_next: %d", state_next);
		      $display("req_next: %d", rd_req_next);			    
         end
         // this state intended to wait the comb circ 
         NOP1: begin
            state_next = WRITE_ADDR1;
         end
         WRITE_ADDR1: begin
            if (!in_fifo_sram_empty) begin
               wr_req_next = 1'b1;
               wr_addr_next = low_addr;
               if(hash_is_ack) begin
                  wr_data_next = updated_ack;
               end
               else begin
                  wr_data_next = updated_data;
               end
               state_next = WAIT_WR_ADDR1;
            end
         end
        
         WAIT_WR_ADDR1: begin
         
         	write_persistence(wr_ack,delay,delay_next,wr_req_next,state_next,
         					WAIT_WR_ADDR1,/*WRITE_ADDR2*/NOP2,in_fifo_sram_rd_en);
         	
         	if(wr_ack) begin
	   	      medicao1_next = latencia;
   	      end				
         					
         end
         // this state intended to wait the comb circ 
         NOP2: begin
            state_next = WRITE_ADDR2;
         end
         WRITE_ADDR2: begin
            wr_req_next = 1;
            wr_addr_next = high_addr;
            if(hash_is_ack) begin
               wr_data_next = updated_ack;
            end
            else begin
               wr_data_next = updated_data;
            end
            state_next = WAIT_WR_ADDR2;
         end
         WAIT_WR_ADDR2: begin
            
         	write_persistence(wr_ack,delay,delay_next,wr_req_next,state_next,
         					WAIT_WR_ADDR2,PAYLOAD1,in_fifo_sram_rd_en);
         					
         	if(wr_ack) begin
	   	      medicao2_next = latencia;

            // we don't record in fifo when pkt is not ack
               if(!hash_is_ack) begin
                  /* catch next tuple */
                  in_fifo_hash_rd_en = 1;

                  // free shift.v
                  bloom_filter_disable_nxt = 1'b0;
                  state_next =REQ_SHIFT_STOP; //ADDR1;
               end
   	      end


         end
         PAYLOAD1: begin
         /* write in fifo the word with results */
         /* if fifo is full, discard */
            if(!in_fifo_med_full) begin 
               in_fifo_med_din = tuple[95:32]; //ip1 e ip2
               in_fifo_med_wr =1'b1;
               state_next = PAYLOAD2;
            end
            /*   state_next = ADDR1;
            end else
               state_next = PAYLOAD2;*/
         end
         PAYLOAD2: begin
            in_fifo_med_din = {tuple[31:0],medicao};
            in_fifo_med_wr =1'b1;
            /* catch next tuple */
            in_fifo_hash_rd_en = 1'b1;

            // free shift.v
            bloom_filter_disable_nxt = 1'b0;
            state_next =REQ_SHIFT_STOP;//ADDR1;
         end
         default: begin
            $display("DEFAULT BLOOM FILTER\n");
            $stop;
         end
	 	endcase
	 end
	 
	 always @(posedge clk) begin
	 	if (reset) begin
	 		state             <= REQ_SHIFT_STOP; //ADDR1;
         wr_data           <= {SRAM_DATA_WIDTH{1'b0}};
	 	   {rd_req,wr_req}   <= 2'b0;
         rd_addr           <= {SRAM_ADDR_WIDTH{1'b0}};
         wr_addr           <= {SRAM_ADDR_WIDTH{1'b0}};
         medicao1          <= {BITS_SHIFT{1'b0}};
         medicao2          <= {BITS_SHIFT{1'b0}};
         cur_bucket        <= 'h0;
         cur_loop          <='h0;
         
         // bucket and loop in search
         _bucket <=0;
         _loop <=0;

         // persistence
         delay <=0;

         data_aft_shft <= {SRAM_DATA_WIDTH{1'b0}};

         // bloom filter vs shift
         bloom_filter_disable <= 1'b0;

	 	end else begin
         if(watchdog) begin
            $display("bloom_watchdog\n");
            /* updates bloom filter counter */
            if(cur_bucket == 13)  begin
               cur_loop    <= cur_loop + 'h1;
               cur_bucket  <= 'h0;
            end
            else begin
               cur_bucket  <= cur_bucket+'h1;
               cur_loop    <= cur_loop;
            end

         end 
         //else begin
         state          <= state_next;
         wr_data        <= wr_data_next;
         rd_req         <= rd_req_next;
         wr_req         <= wr_req_next;
         rd_addr        <= /*rd_addr_next;//*/{{9{1'b0}},rd_addr_next[9:0]};
         wr_addr        <= /*wr_addr_next;//*/{{9{1'b0}},wr_addr_next[9:0]};
         medicao1       <= medicao1_next;
         medicao2       <= medicao2_next;
         //end
         
         // persistence
         delay          <= delay_next;

         // bucket and loop
         _bucket        <= _bucket_nxt;
         _loop          <= _loop_nxt;

         data_aft_shft  <= dado_deslocado;

         // bloom filter vs shift
         bloom_filter_disable <= bloom_filter_disable_nxt;

      end	
	 end //always @(posedge clk)

   /* DEBUG */
   //synthesis translate_off
   always @(posedge clk) begin
      /*if(state_next == WAIT_ADDR1)
         $display("WAIT_ADDR1\n");
      if(state_next == WAIT_ADDR2)
         $display("WAIT_ADDR2\n");
      if(rd_ack)
         $display("RECV ACK\n");
      if(in_fifo_hash_full) begin
         $display("FIFO HASH FULL\n");
         $stop;
      end*/
      if(state_next == ADDR1 && !in_fifo_hash_empty && enable) begin
         $display("HASH FIFO: %h %h\n",addr1,addr2);
      end
      if(rd_req)
         $display("readding: %h\n",rd_addr);
      if(rd_vld)
         $display("readdata: %h %h\n",rd_vld,rd_data);
      if(in_wr) 
         $display("idx0: %h, idx1: %h,tuple: %h\n",index_0,index_1,tuple); 
      if(in_fifo_med_wr)
         $display("in_fifo_med_din: %h\n",in_fifo_med_din);
      /*if(state_next == WAIT_ADDR1 && rd_req_next)
            $display("lowaddr: %h\n",low_addr[9:0]);
      if(state_next == WAIT_ADDR2 && rd_req_next)
            $display("highaddr: %h\n",high_addr[9:0]);*/
      if(state_next == WRITE_ADDR2 && hash_is_ack)
         $display("medicao1: %h, indice: %b, deslocado: %h: %h %h\n",latencia,indice,dado_deslocado,in_fifo_sram_dout,wr_addr);
      if(state_next == PAYLOAD1 && hash_is_ack)
         $display("medicao2: %h, indice: %b, deslocado: %h: %h %h\n",latencia,indice,dado_deslocado,in_fifo_sram_dout,wr_addr);
      if((state_next == WAIT_WR_ADDR1 || state_next == WAIT_WR_ADDR2) && wr_req_next) begin
         if(hash_is_ack) 
            $display("hashisack:%d,%h|%h\n",hash_is_ack,updated_ack,wr_addr_next);
         else
            $display("hashisdata:%d,%h|%h\n",hash_is_ack,updated_data,wr_addr_next);
      end
   end
   //synthesis translate_on
    
endmodule
