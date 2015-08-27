///////////////////////////////////////////////////////////////////////////////
// Module: calcula_latencia.v
// Project: temp 
// Description: the index regarding the i-th bucket will be filled with 1 while 
// the others will be filled with 0 
///////////////////////////////////////////////////////////////////////////////

// numero de buckets fixo
module calcula_latencia
		#(	
			parameter INDEX_WIDTH = 14,
      	parameter BITS_SHIFT = 7)
	   (
		input	[INDEX_WIDTH-1:0]						index,
		output reg [BITS_SHIFT-1:0]				latencia);

	always @(index) begin
      
      case(index)
      0: begin
         latencia ={BITS_SHIFT{1'b1}}; //ignorar este valor

      end
      1: begin
         latencia = 13;

      end
      2: begin
         latencia = 12;

      end
      4: begin
         latencia = 11;

      end
      8: begin
         latencia = 10;

      end
      16: begin
         latencia = 9;

      end
      32: begin
         latencia = 8;
      
      end
      64: begin
         latencia = 7;

      end
      128: begin
         latencia = 6;

      end
      256: begin
         latencia = 5;

      end
      512: begin
         latencia = 4;

      end
      1024: begin
         latencia = 3;

      end
      2048: begin
         latencia = 2;

      end
      4096: begin
         latencia = 1;

      end
      8192: begin
         latencia = 0;

      end
      endcase
		$display("index :%b\n",index);
		$display("latencia :%x\n",latencia);
	end
endmodule // hash
