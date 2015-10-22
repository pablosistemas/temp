///////////////////////////////////////////////////////////////////////////////
// Module: lookup_bucket.v
// Project: temp 
// Description: 
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module atualiza_linha
   #(	
			parameter DATA_WIDTH = 72,
   		parameter NUM_BUCKETS = 14,
      	parameter BUCKET_SZ = 4,
         parameter BITS_SHIFT = 4,
      	parameter BLOOM_INIT_POS = 16)
	(
		input	[DATA_WIDTH-1:0]						data,
		output reg [DATA_WIDTH-1:0]				output_data,

      input [BITS_SHIFT-1:0]                 cur_bucket,
      input [BLOOM_INIT_POS-BITS_SHIFT-1:0]  cur_loop	
   );

   reg [BITS_SHIFT-1:0]                      shifts;
   wire [BITS_SHIFT-1:0]                     data_bucket;
   wire [BLOOM_INIT_POS-BITS_SHIFT-1:0]      data_loop;
   wire [DATA_WIDTH-BLOOM_INIT_POS-1:0]      data_bloom;   

   /* data fields */
   assign data_loop 		= data[BLOOM_INIT_POS-BITS_SHIFT-1:0];
   assign data_bucket 	= data[BLOOM_INIT_POS-1:BLOOM_INIT_POS-BITS_SHIFT];
   assign data_bloom 	= data[DATA_WIDTH-1:BLOOM_INIT_POS];

   //always @(data) begin
   always @(*) begin
      
		shifts = 0;

      if(cur_loop < data_loop) begin
         $display("loop ERROR: %h,buck: %d, loop: %d\n",data,cur_bucket,cur_loop);
			//if addr was previously updated by write data|ack op
			// this case will be used in counter overflow
         if(({1'b1,cur_loop} - (data_loop)) > 'h1) begin
            shifts = NUM_BUCKETS; //zera linha
			end
         else begin
            shifts = NUM_BUCKETS-data_bucket+cur_bucket;
			end
      end
		
      else if(cur_loop == data_loop) begin
         $display("bucket ERROR: %h, buck: %d, loop: %d\n",data,cur_bucket,cur_loop);
			//if addr was previously updated by write data|ack op
			if(cur_bucket < data_bucket) begin
				// do nothing;
			end
			else begin
				shifts = (cur_bucket-data_bucket);
			end
      end
			
      else if(cur_loop > data_loop) begin
         if(cur_bucket < data_bucket) begin
            shifts = NUM_BUCKETS-data_bucket+cur_bucket;
			end
         else begin
            shifts = NUM_BUCKETS;
			end
      end
		
      else begin
			// undefined states
         $display("loop: %h|%h, buck: %h|%h\n",cur_loop,data_loop,cur_bucket,data_bucket);
      end
   end

   /* output */
   always @(*) begin
      if(cur_loop > data_loop) begin
         output_data[BLOOM_INIT_POS-1:BLOOM_INIT_POS-BITS_SHIFT] =cur_bucket;
         output_data[BLOOM_INIT_POS-BITS_SHIFT-1:0] =cur_loop;
      end
      else if (data_loop > cur_loop) begin
         // $display("ERROR: data_loop updated earlier. Data_loop > cur_loop\n");
         output_data[BLOOM_INIT_POS-1:BLOOM_INIT_POS-BITS_SHIFT] =data_bucket;
         output_data[BLOOM_INIT_POS-BITS_SHIFT-1:0] =data_loop;
      end
      else begin
         output_data[BLOOM_INIT_POS-1:BLOOM_INIT_POS-BITS_SHIFT] =cur_bucket>data_bucket?cur_bucket:data_bucket;
         output_data[BLOOM_INIT_POS-BITS_SHIFT-1:0] =cur_loop;
      end

      case(shifts)
         0: output_data[DATA_WIDTH-1:BLOOM_INIT_POS] = data_bloom;
         1: output_data[DATA_WIDTH-1:BLOOM_INIT_POS] = {{BUCKET_SZ{1'b0}},data_bloom[DATA_WIDTH-BLOOM_INIT_POS-1:BUCKET_SZ]};
         2: output_data[DATA_WIDTH-1:BLOOM_INIT_POS] = {{(2*BUCKET_SZ){1'b0}},data_bloom[DATA_WIDTH-BLOOM_INIT_POS-1:2*BUCKET_SZ]};
         3: output_data[DATA_WIDTH-1:BLOOM_INIT_POS] = {{(3*BUCKET_SZ){1'b0}},data_bloom[DATA_WIDTH-BLOOM_INIT_POS-1:3*BUCKET_SZ]};
         4: output_data[DATA_WIDTH-1:BLOOM_INIT_POS] = {{(4*BUCKET_SZ){1'b0}},data_bloom[DATA_WIDTH-BLOOM_INIT_POS-1:4*BUCKET_SZ]};
         5: output_data[DATA_WIDTH-1:BLOOM_INIT_POS] = {{(5*BUCKET_SZ){1'b0}},data_bloom[DATA_WIDTH-BLOOM_INIT_POS-1:5*BUCKET_SZ]};
         6: output_data[DATA_WIDTH-1:BLOOM_INIT_POS] = {{(6*BUCKET_SZ){1'b0}},data_bloom[DATA_WIDTH-BLOOM_INIT_POS-1:6*BUCKET_SZ]};
         7: output_data[DATA_WIDTH-1:BLOOM_INIT_POS] = {{(7*BUCKET_SZ){1'b0}},data_bloom[DATA_WIDTH-BLOOM_INIT_POS-1:7*BUCKET_SZ]};
         8: output_data[DATA_WIDTH-1:BLOOM_INIT_POS] = {{(8*BUCKET_SZ){1'b0}},data_bloom[DATA_WIDTH-BLOOM_INIT_POS-1:8*BUCKET_SZ]};
         9: output_data[DATA_WIDTH-1:BLOOM_INIT_POS] = {{(9*BUCKET_SZ){1'b0}},data_bloom[DATA_WIDTH-BLOOM_INIT_POS-1:9*BUCKET_SZ]};
         10: output_data[DATA_WIDTH-1:BLOOM_INIT_POS] = {{(10*BUCKET_SZ){1'b0}},data_bloom[DATA_WIDTH-BLOOM_INIT_POS-1:10*BUCKET_SZ]};
         11: output_data[DATA_WIDTH-1:BLOOM_INIT_POS] = {{(11*BUCKET_SZ){1'b0}},data_bloom[DATA_WIDTH-BLOOM_INIT_POS-1:11*BUCKET_SZ]};
         12: output_data[DATA_WIDTH-1:BLOOM_INIT_POS] = {{(12*BUCKET_SZ){1'b0}},data_bloom[DATA_WIDTH-BLOOM_INIT_POS-1:12*BUCKET_SZ]};
         13: output_data[DATA_WIDTH-1:BLOOM_INIT_POS] = {{(13*BUCKET_SZ){1'b0}},data_bloom[DATA_WIDTH-BLOOM_INIT_POS-1:13*BUCKET_SZ]};
         default: begin
            output_data[DATA_WIDTH-1:BLOOM_INIT_POS] = 'h0; //data_bloom;
            $display("DEFAULT,%d %h\n",shifts,output_data);
         end
      endcase
   end

endmodule // hash
