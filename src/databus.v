///////////////////////////////////////////////////////////////////////////////
// vim:set shiftwidth=3 softtabstop=3 expandtab:
// $Id: module_template 2008-03-13 gac1 $
//
// Module: 
// Project:
//
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module databus
   #(
      parameter DATA_WIDTH = 64,
      parameter CTRL_WIDTH = 8,
      parameter SRAM_ADDR_WIDTH = 19,
      parameter SRAM_DATA_WIDTH = DATA_WIDTH+CTRL_WIDTH,
      parameter WORD_WIDTH = 64,
      parameter UDP_REG_SRC_WIDTH = 2)
   (
      input  [DATA_WIDTH-1:0]             in_data,
      input  [CTRL_WIDTH-1:0]             in_ctrl,
      input                               in_wr,
      output                              in_rdy,

      output reg [DATA_WIDTH-1:0]         out_data,
      output reg [CTRL_WIDTH-1:0]         out_ctrl,
      output reg                          out_wr,
      input                               out_rdy,

      // --- Register interface
      input                               reg_req_in,
      input                               reg_ack_in,
      input                               reg_rd_wr_L_in,
      input  [`UDP_REG_ADDR_WIDTH-1:0]    reg_addr_in,
      input  [`CPCI_NF2_DATA_WIDTH-1:0]   reg_data_in,
      input  [UDP_REG_SRC_WIDTH-1:0]      reg_src_in,

      output                              reg_req_out,
      output                              reg_ack_out,
      output                              reg_rd_wr_L_out,
      output  [`UDP_REG_ADDR_WIDTH-1:0]   reg_addr_out,
      output  [`CPCI_NF2_DATA_WIDTH-1:0]  reg_data_out,
      output  [UDP_REG_SRC_WIDTH-1:0]     reg_src_out,

      // interface to payload fifo
      input [WORD_WIDTH-1:0]              pld_fifo_din,
      output                              pld_fifo_full,
      input                               pld_fifo_wr,

      // misc
      input                                reset,
      input                                clk
   );

   // Define the log2 function
   `LOG2_FUNC

   /* calcula sinal de controle da ultima palavra 
   * com base no tamanho de uma palavra do dado. */
   function integer calcula_last_ctrl;
      input reg [7:0] length;
      input [3:0] ctrl_width;
      input [7:0] data_width;

      integer i;
      begin
         i=0;
         while (i*ctrl_width<(length%data_width)) begin
            i=i+1;
         end
         calcula_last_ctrl = 1<<(ctrl_width-i);
      end
   endfunction

   localparam          WAIT_PKT =1;
   localparam          WAIT_END_OF_PKT =2;
   localparam          SEND_EVT_HDR =4;
   localparam          SEND_EVT_PAYLOAD =8;

   localparam          NUM_STATES =4;

   /* ao mudar o numero de palavras no payload
   * eh necessario mudar o tamanho do pacote no metacabecalho
   * em cria_pks.v */

  /* Simulação - mudar aqui */
  /* The number of measurements is NUM_PAYLOAD/2 */
   localparam          NUM_WORDS_PAYLOAD = /*300; //*/20;//8 for test
   localparam          NUM_WORDS_IN_HDR =7;
   /* */
   localparam          CTRL_LAST_WORD=calcula_last_ctrl(NUM_WORDS_PAYLOAD,CTRL_WIDTH,DATA_WIDTH);


   //------------------------- Signals-------------------------------
   
   wire [DATA_WIDTH-1:0]         in_fifo_data;
   wire [CTRL_WIDTH-1:0]         in_fifo_ctrl;
   wire                          in_fifo_full;
   wire                          in_fifo_empty;
   reg                           in_fifo_rd_en;

   /* interface to bloom filter */

   wire [WORD_WIDTH-1:0]         pld_fifo_dout;
   wire                          pld_fifo_nearly_full;
   wire                          pld_fifo_empty;
   reg                           pld_fifo_rd_en;

   reg                           evt_pkt_sent;
   reg [8:0]                     num_words_sent;
   reg [8:0]                     num_words_sent_next;

   reg [2:0]                     word_num, word_num_next;

   reg [NUM_STATES-1:0]          state, state_next;
     
  /* interface to cria_pkts */ 
   wire [DATA_WIDTH-1:0]         header_data;
   wire [CTRL_WIDTH-1:0]         header_ctrl;

   //----------------- Local assignments ---------------------

   assign in_rdy     = !in_fifo_full;

   //------------------------- Modules-------------------------------

   fallthrough_small_fifo_old #(
      .WIDTH(CTRL_WIDTH+DATA_WIDTH),
      .MAX_DEPTH_BITS(3)
   ) input_fifo (
      .din           ({in_ctrl, in_data}),// Data in
      .wr_en         (in_wr), // Write enable
      .rd_en         (in_fifo_rd_en), // Read the next word
      .dout          ({in_fifo_ctrl, in_fifo_data}),
      .full          (in_fifo_full),
      .nearly_full   (),
      .empty         (in_fifo_empty),
      .reset         (reset),
      .clk           (clk)
   );

   /* medicoes em payload: 2**MAX_DEPTH_BITS/2 */
   /* envia apenas se houver, no minimo, NUM_WORDS_PAYLOAD */ 
   fallthrough_small_fifo_old #(
      .WIDTH(WORD_WIDTH),
      .MAX_DEPTH_BITS(10),//(log2(NUM_WORDS_PAYLOAD)+1),
      .NEARLY_FULL(NUM_WORDS_PAYLOAD) 
   ) pld_fifo (
      .din           (pld_fifo_din),//Data in
      .wr_en         (pld_fifo_wr), // Write enable
      .rd_en         (pld_fifo_rd_en),
      .dout          (pld_fifo_dout),
      .full          (pld_fifo_full),
      .nearly_full   (pld_fifo_nearly_full),
      .empty         (pld_fifo_empty),
      .reset         (reset),
      .clk           (clk)
   );

   cria_pkts #(
      .DATA_WIDTH          (DATA_WIDTH),
      .NUM_WORDS_PAYLOAD   (NUM_WORDS_PAYLOAD),   
      .HEADER_LENGTH       (NUM_WORDS_IN_HDR)
   ) cria_pkts (
      .reg_req_in          (reg_req_in), 
      .reg_ack_in          (reg_ack_in),           
      .reg_rd_wr_L_in      (reg_rd_wr_L_in),
      .reg_addr_in         (reg_addr_in),
      .reg_data_in         (reg_data_in),
      .reg_src_in          (reg_src_in),

      .reg_req_out         (reg_req_out), 
      .reg_ack_out         (reg_ack_out),           
      .reg_rd_wr_L_out     (reg_rd_wr_L_out),
      .reg_addr_out        (reg_addr_out),
      .reg_data_out        (reg_data_out),
      .reg_src_out         (reg_src_out),

      .header_word_number  (word_num),
      .evt_pkt_sent        (evt_pkt_sent),
      .header_data         (header_data),
      .header_ctrl         (header_ctrl),
      .enable              (enable),

      .reset            (reset),
      .clk              (clk)
   );

   //------------------------- Logic-------------------------------
   //

   always @(*) begin
      // Default values
      {out_ctrl,out_data} = {in_fifo_ctrl,in_fifo_data};
      /* fifo */
      in_fifo_rd_en = 0;
      pld_fifo_rd_en = 0;
      /* module */
      out_wr =0;
      evt_pkt_sent =0;
      num_words_sent_next =num_words_sent;

      state_next = state;

      word_num_next = word_num;

      case(state)
         WAIT_PKT: begin
            if(out_rdy) begin
               if(pld_fifo_nearly_full) begin
                  $display("nearly_full\n");
                  state_next = SEND_EVT_HDR;
                  word_num_next = word_num+1;
                  out_ctrl = header_ctrl; //check
                  // synthesis translate_off
                  if(header_ctrl != `IO_QUEUE_STAGE_NUM) begin
                     $display("testeIOQ\n");
                     $stop;
                  end
                  // synthesis translate_on
                  out_data = header_data;
                  out_wr = 1;
               end 
               else if(!in_fifo_empty) begin 
                  in_fifo_rd_en = 1;
                  out_wr = 1;
                  if(in_fifo_ctrl == 'h0)
                     state_next = WAIT_END_OF_PKT;
               end
            end
         end
         WAIT_END_OF_PKT: begin
            if(!in_fifo_empty && out_rdy) begin
               if(in_fifo_ctrl != `IO_QUEUE_STAGE_NUM) begin
                  in_fifo_rd_en = 1;
                  out_wr = 1;
                  state_next = WAIT_END_OF_PKT;
               end
               else if(in_fifo_ctrl == `IO_QUEUE_STAGE_NUM) begin
                  state_next = WAIT_PKT;
               end

               /*if(in_fifo_ctrl != 0)
                  state_next = WAIT_PKT;
               in_fifo_rd_en = 1;
               out_wr = 1;*/
            end
         end
         SEND_EVT_HDR: begin
            if(out_rdy) begin
               //if(header_ctrl != 0)
               //   $stop;
               if(word_num < NUM_WORDS_IN_HDR) begin
                  word_num_next = word_num + 1;
                  out_ctrl = header_ctrl; //check
                  out_data = header_data;
                  out_wr = 1;
               end else begin
                  state_next = SEND_EVT_PAYLOAD;
                  word_num_next = 0; //reset value to next pkt
               end
            end
         end
         SEND_EVT_PAYLOAD: begin
            if(out_rdy) begin
               //synthesis translate_off
               if(pld_fifo_empty)
                  $stop;
               //synthesis translate_on
               if(num_words_sent < NUM_WORDS_PAYLOAD-1) begin
                  out_ctrl = 8'h0;
                  out_data = pld_fifo_dout;
                  out_wr = 1;
                  pld_fifo_rd_en = 1;
                  num_words_sent_next = num_words_sent+1;
               end else begin
            /* marca fim do pacote */
            /* ctrl da ultima palavra igual ao byte final */
                  out_ctrl = 8'h1;
                  out_data = pld_fifo_dout;
                  out_wr = 1;
                  pld_fifo_rd_en = 1;
                  evt_pkt_sent =1;
                  /* reset */
                  state_next = WAIT_PKT;
                  num_words_sent_next =0;
               end
            end
         end
         default: begin
         //systhesis translate_off
            $stop;
         //systhesis translate_on
         end
      endcase
   end

   always @(posedge clk) begin
      if(reset) begin
         state <=WAIT_PKT;
         num_words_sent <=0;
         word_num <=0;
         num_words_sent <= 0;
      end
      else begin
         state <=state_next;
         num_words_sent <=num_words_sent_next;
         word_num <=word_num_next;
      end
   end

   //synthesis translate_off
   always @(posedge clk) begin
      if(out_wr && (state_next==WAIT_PKT||
         state_next==SEND_EVT_HDR) && pld_fifo_nearly_full) begin
         $display("header_ctrl:%h|header_data:%h\n",out_ctrl,out_data);
      end
      if(state_next==SEND_EVT_PAYLOAD && out_wr) begin
         $display("payload_ctrl:%h|payload_data:%h|%b\n",out_ctrl,out_data,CTRL_LAST_WORD);
      end
      if(out_wr)
         $display("Ctrl:%h|Data:%h\n",out_ctrl,out_data);
   end
   //synthesis translate_on
   
endmodule
