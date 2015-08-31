///////////////////////////////////////////////////////////////////////////////
// Module: lookup_bucket.v
// Project: temp 
// Description: the index regarding the i-th bucket will be filled with 1 while 
// the others will be filled with 0 
///////////////////////////////////////////////////////////////////////////////

module lookup_bucket
		#(	
			parameter INPUT_WIDTH = 72,
   		parameter NUM_BUCKETS = 12,
      	parameter BUCKET_SZ = 4,
      	parameter OUTPUT_WIDTH = NUM_BUCKETS)
	(
		input	[INPUT_WIDTH-1:0]						data,
		output [OUTPUT_WIDTH-1:0]					index
	);

	/* local assignments */
	assign index[OUTPUT_WIDTH-1] = (data[INPUT_WIDTH-1:INPUT_WIDTH-BUCKET_SZ] > 0)?1:0;
   
		/*generate
		genvar i;
		for(i=OUTPUT_WIDTH-2; i >= 0; i=i-1) begin
			assign index[i] = ~index[i+1];
		end
		endgenerate*/
   generate
      genvar i, j;
      for (i=OUTPUT_WIDTH-2; i >= 0; i=i-1) begin: one_in_ith_bucket
      	//assign index[i] = ~(index[i+1]);
         /*for (j=i+2; j < OUTPUT_WIDTH; j=j+1) begin: tt
	 			assign index[i] = index[i]&(~index[j]);
         end*/
      	assign index[i] = (index[OUTPUT_WIDTH-1:i+1]>0?0:1)&((data[INPUT_WIDTH-1-(OUTPUT_WIDTH-i-1)*BUCKET_SZ:INPUT_WIDTH-1-(OUTPUT_WIDTH-i)*BUCKET_SZ-1]>0)?1:0);
      end
   endgenerate
	
	/*always @(data,index) begin
		$display("data :%h\n",data);
		$display("index :%b\n",index);
	end*/
endmodule // hash
