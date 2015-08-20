///////////////////////////////////////////////////////////////////////////////
// vim:set shiftwidth=3 softtabstop=3 expandtab:
// $Id$
//
// Module: watchdog.v
// Project: temp
// Author:
// Description: TIMER_LIMIT parameter is taken has the number of clock cycles
// until firing of update signal
///////////////////////////////////////////////////////////////////////////////

module watchdog
  #( parameter TIMER_LIMIT = 'h3fff_ffff) (
	// --- updates the current bucket in bloom filter
    output reg                         update,

    // --- Misc
    input                              enable,
    input                              clk,
    input                              reset);

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
   //------------------ Internal Parameters --------------------------
   localparam TIMER_LIMIT_BITS = log2(TIMER_LIMIT);
   //---------------------- Wires/Regs -------------------------------

   reg [TIMER_LIMIT_BITS-1:0]            watchdog_counter;


   //------------------------ Logic ----------------------------------

   always @(posedge clk) begin
      if(reset) begin
         watchdog_counter <= 0;
      end else if (enable) begin
         if(update)
            watchdog_counter <= 0;
         else
            watchdog_counter <= watchdog_counter + 1;
      end else
         watchdog_counter <= watchdog_counter;
   end

   always @(posedge clk) begin
      if(reset) begin
         update <= 0;
      end
      else begin
         if (watchdog_counter == TIMER_LIMIT - 1) begin
            update <= 1;
         end
         else begin
            update <= 0;
         end
      end
   end

   /* DEBUG */
   //synthesis translate_off
   always @(posedge clk) begin
      $display("wdcounter: %d\n",watchdog_counter);
      if(update)
         $display("wdupdate\n");
   end
   //synthesis translate_on

endmodule
