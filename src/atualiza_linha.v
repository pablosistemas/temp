///////////////////////////////////////////////////////////////////////////////
// Module: lookup_bucket.v
// Project: temp 
// Description: 
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module atualiza_linha
   #(	
			parameter DATA_WIDTH = 72,
   		parameter NUM_BUCKETS = 12,
      	parameter BUCKET_SZ = 4,
         parameter BITS_SHIFT = log2(NUM_BUCKETS),
      	parameter BLOOM_INIT_POS = 16)
	(
		input	[DATA_WIDTH-1:0]						data,
		output [DATA_WIDTH-1:0]					   output_data,

      input [BITS_SHIFT-1:0]                 cur_bucket,
      input [BLOOM_INIT_POS-BITS_SHIFT-1:0]  cur_loop	
   );

   //`LOG2_FUNC
	function integer log2;
		input integer number;
		begin
			log2=0;
			while(2**log2<number) begin
				log2 = log2+1;
			end
		end	
	endfunction
	

   reg [BITS_SHIFT-1:0]                      shifts;
   wire [BITS_SHIFT-1:0]                     data_bucket;
   wire [BLOOM_INIT_POS-BITS_SHIFT-1:0]      data_loop;
   wire [DATA_WIDTH-BLOOM_INIT_POS-1:0]      data_bloom;   

   /* data fields */
   assign data_loop = data[BLOOM_INIT_POS-BITS_SHIFT-1:0];
   assign data_bucket = data[BLOOM_INIT_POS-1:BLOOM_INIT_POS-BITS_SHIFT];
   assign data_bloom = data[DATA_WIDTH-1:BLOOM_INIT_POS];

   /* output */
   assign output_data = {data_bloom>>shifts*BUCKET_SZ,cur_bucket,cur_loop};

   always @(data) begin
      //synthesis translate_off
      if(cur_loop < data_loop) begin
         $display("loop ERROR\n");
         $stop;
      end
      if(cur_loop==data_loop && cur_bucket<data_bucket) begin
         $display("bucket ERROR\n");
         $stop;
      end
      //synthesis translate_on
      if(cur_loop == data_loop && cur_bucket >= data_bucket)
         shifts = (cur_bucket-data_bucket);
      else if(cur_loop > data_loop) begin
         shifts = (cur_loop-1-data_loop)*((NUM_BUCKETS-1)-data_bucket+cur_bucket);
      end
   end

endmodule // hash
