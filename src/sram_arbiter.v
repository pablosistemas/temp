///////////////////////////////////////////////////////////////////////////////
// $Id: sram_arbiter.v 5697 2009-06-17 22:32:11Z tyabe $
//
// Module: sram_arbiter.v
// Project: Firewall 
// Description: controlador SRAM
//
// Provê acesso para a SRAM para consultas dos módulos e registradores.
// Prioiridade do acesso: rd/wr pela interface de registradores, escrita pelos módulos,
// leitura pelos módulos.
//
///////////////////////////////////////////////////////////////////////////////

`timescale  1ns /  10ps

module sram_arbiter  #(parameter SRAM_ADDR_WIDTH = 19,
                       parameter SRAM_DATA_WIDTH = 36,
                       parameter SHIFT_WIDTH = SRAM_ADDR_WIDTH )

   (// register interface
    input                            sram_reg_req,
    input                            sram_reg_rd_wr_L,    // 1 = read, 0 = write
    input [`SRAM_REG_ADDR_WIDTH-1:0] sram_reg_addr,
    input [`CPCI_NF2_DATA_WIDTH-1:0] sram_reg_wr_data,

    output reg                             sram_reg_ack,
    output reg [`CPCI_NF2_DATA_WIDTH -1:0] sram_reg_rd_data,

    // --- Requesters (read and/or write)
    input                              wr_0_req,
    input [SRAM_ADDR_WIDTH-1:0]        wr_0_addr,
    input [SRAM_DATA_WIDTH-1:0]        wr_0_data,
    output reg                         wr_0_ack,

    input                              rd_0_req,
    input [SRAM_ADDR_WIDTH-1:0]        rd_0_addr, 
    output reg [SRAM_DATA_WIDTH-1:0]   rd_0_data,
    output reg                         rd_0_ack,
    output reg                         rd_0_vld,

    // --- Requesters BLOOMFILTER shifter
    input                              wr_1_req,
    input [SRAM_ADDR_WIDTH-1:0]        wr_1_addr,
    input [SRAM_DATA_WIDTH-1:0]        wr_1_data,
    output reg                         wr_1_ack,

    input                              rd_1_req,
    input [SRAM_ADDR_WIDTH-1:0]        rd_1_addr, 
    output reg [SRAM_DATA_WIDTH-1:0]   rd_1_data,
    output reg                         rd_1_ack,
    output reg                         rd_1_vld,

    // --- SRAM signals (pins and control)
    output reg [SRAM_ADDR_WIDTH-1:0]   sram_addr,
    output reg [SRAM_ADDR_WIDTH-1:0]   sram_addr_next,
    output reg                         sram_we,
    output reg [SRAM_DATA_WIDTH/9-1:0] sram_bw,
    output reg [SRAM_DATA_WIDTH-1:0]   sram_wr_data,
    input      [SRAM_DATA_WIDTH-1:0]   sram_rd_data,
    output reg                         sram_tri_en,

    // --- Misc
   
    output                             enable,

    input reset,
    input clk

    );

   //------------------ Registers/Wires -----------------
   reg                       rd_0_vld_early2, rd_0_vld_early1, rd_0_vld_early3;
   reg                       rd_1_vld_early2, rd_1_vld_early1, rd_1_vld_early3;
   reg [SRAM_DATA_WIDTH-1:0] sram_wr_data_early2, sram_wr_data_early1;
   reg                       sram_tri_en_early2, sram_tri_en_early1;
   reg                       sram_reg_ack_early3, sram_reg_ack_early2, sram_reg_ack_early1;

   reg                       sram_reg_addr_is_high, sram_reg_addr_is_high_d1, sram_reg_addr_is_high_d2;
   reg                        do_reset;

   assign enable = ~do_reset;

   always @(posedge clk) begin
      if(reset) begin
         {sram_we,sram_bw}    <= 9'h1ff;
         sram_addr             <= 0;
         sram_addr_next        <= 0;
         do_reset              <= 1'b1;
	 // synthesis translate_off
         //do_reset              <= 0;
	 // synthesis translate_on
         sram_reg_ack         <= 0;
         {rd_0_vld,rd_1_vld}    <= 2'b0;

         // persistence
         {rd_0_vld_early1,rd_1_vld_early1} <=2'b0;
         {rd_0_vld_early2,rd_1_vld_early2} <=2'b0;
         {rd_0_vld_early3,rd_1_vld_early3} <=2'b0;
      end
      else begin
         if(do_reset) begin
            if(sram_addr == {{(SRAM_ADDR_WIDTH-SHIFT_WIDTH){1'b0}},{SHIFT_WIDTH{1'b1}}}) begin
               do_reset               <= 0;
               {sram_we, sram_bw}     <= -1; // active low
               {rd_0_ack,rd_1_ack}    <= 2'b0;
               {rd_0_vld,rd_1_vld}    <= 2'b0;
               {wr_0_ack,wr_1_ack}    <= 2'b0;
            end
            else begin
               //sram_addr              <= sram_addr + 1'b1;
               sram_addr               <= sram_addr_next;
               sram_addr_next          <= sram_addr_next+1'b1;
               {sram_we, sram_bw}     <= 9'h0;

               sram_wr_data_early2 <=0;

               //synthesis translate_off
               //sram_wr_data_early2    <= {3'b0,sram_addr_next,{(SRAM_DATA_WIDTH-16){1'b0}}}; 
               // synthesis translate_on
               sram_tri_en_early2     <= 1;
               
               // persistence
               {rd_0_ack,rd_1_ack,wr_0_ack,wr_1_ack} <= 4'b0;

            end // else: !if(sram_addr == {SRAM_ADDR_WIDTH{1'b1}})
         end // if (do_reset)

         else begin
            /* Default values */
            {rd_0_ack,wr_0_ack} <= 2'b0;
            {rd_1_ack,wr_1_ack} <= 2'b0;
            {rd_0_vld_early3,rd_1_vld_early3} <= 2'b0;
            sram_reg_ack_early3 <= 0;

         //first pipeline stage
            sram_reg_addr_is_high <= sram_reg_addr[0];
            if(sram_reg_req) begin
               sram_addr <= sram_reg_addr[19:1];
               sram_wr_data_early2 <= sram_reg_addr[0] ? {sram_reg_wr_data,36'b0}:{36'h0,sram_reg_wr_data};
               sram_tri_en_early2 <= !sram_reg_rd_wr_L && sram_reg_req;
               if(!sram_reg_rd_wr_L) begin
                  sram_bw <= sram_reg_addr[0] ? 8'h0f : 8'hf0;
                  sram_we <= 1'b0;
               end
               else begin //leitura
                  sram_bw <= 8'hff;
                  sram_we <= 1'b1;
               end
               sram_reg_ack_early3 <= sram_reg_req;
            end
            else if(wr_0_req) begin
               $display("wr0req\n");
               sram_addr <= wr_0_addr;
               sram_wr_data_early2 <= wr_0_data;
               sram_tri_en_early2 <= wr_0_req;
               sram_we <= 1'b0;
               sram_bw <= 8'h00;
               wr_0_ack <= 1;
            end
            else if(rd_0_req) begin
               $display("rd0req\n");
               sram_bw <= 8'hff;
               sram_we <= 1'b1;
               sram_addr <= rd_0_addr;
               sram_tri_en_early2 <= 0;
               rd_0_vld_early3 <= rd_0_req;
               rd_0_ack <= rd_0_req;
            end
            else if(wr_1_req) begin
               $display("wr1req\n");
               sram_addr <= wr_1_addr;
               sram_wr_data_early2 <= wr_1_data;
               sram_tri_en_early2 <= wr_1_req;
               sram_we <= 1'b0;
               sram_bw <= 8'h00;
               wr_1_ack <= 1;
               //rd_1_vld_early3 <= 0;
            end
            else if(rd_1_req) begin
               sram_bw <= 8'hff;
               sram_we <= 1'b1;
               sram_addr <= rd_1_addr;
               sram_tri_en_early2 <= 0;
               rd_1_vld_early3 <= rd_1_req;
               rd_1_ack <= rd_1_req;
            end
            else begin
               {sram_we,sram_bw} <= 9'h1ff;
               sram_tri_en_early2 <= 1'b0;
               sram_wr_data_early2 <= sram_wr_data_early2;
            end
         end // else: !if(do_reset)
         
         //Second pipeline stage
         sram_tri_en_early1 <= sram_tri_en_early2;
         sram_wr_data_early1 <= sram_wr_data_early2;
         rd_0_vld_early2 <= rd_0_vld_early3;
         rd_1_vld_early2 <= rd_1_vld_early3;
         sram_reg_ack_early2 <= sram_reg_ack_early3;
         sram_reg_addr_is_high_d1 <= sram_reg_addr_is_high;

         //third pipeline stage - Coloca dado e seta tri_en depois de 2 clocks
         sram_tri_en <= sram_tri_en_early1;
         sram_wr_data <= sram_wr_data_early1;
         rd_0_vld_early1 <= rd_0_vld_early2;
         rd_1_vld_early1 <= rd_1_vld_early2;
         sram_reg_ack_early1 <= sram_reg_ack_early2;
         sram_reg_addr_is_high_d2 <= sram_reg_addr_is_high_d1;

         //forth pipeline stage - Coloca dado e seta tri_en depois de 2 clocks
         rd_0_vld <= rd_0_vld_early1;
         rd_1_vld <= rd_1_vld_early1;
         sram_reg_ack <= sram_reg_ack_early1;
         sram_reg_rd_data <= sram_reg_addr_is_high_d2?sram_rd_data[68:36]:sram_rd_data[31:0];
         rd_0_data <= rd_0_vld_early1?sram_rd_data:rd_0_data;
         rd_1_data <= rd_1_vld_early1?sram_rd_data:rd_1_data;

      end // else: !if(reset)
   end // always @ (posedge clk)

endmodule // sram_arbiter
