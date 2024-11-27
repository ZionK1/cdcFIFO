module fifo_1r1w_cdc
 #(parameter [31:0] width_p = 32
  ,parameter [31:0] depth_log2_p = 8
  )
   // To emphasize that the two interfaces are in different clock
   // domains i've annotated the two sides of the fifo with "c" for
   // consumer, and "p" for producer. 
  (input [0:0] cclk_i
  ,input [0:0] creset_i
  ,input [width_p - 1:0] cdata_i
  ,input [0:0] cvalid_i
  ,output [0:0] cready_o 

  ,input [0:0] pclk_i
  ,input [0:0] preset_i
  ,output [0:0] pvalid_o 
  ,output [width_p - 1:0] pdata_o 
  ,input [0:0] pready_i
  );
   
  // Write your code here
  localparam depth_p = 1 << depth_log2_p;

  logic [depth_log2_p:0] rd_ptr_r, rd_ptr_sync, rd_ptr_sync2, rd_b2g_o, rd_g2b_o, rd_g2b_n;
  logic [depth_log2_p:0] wr_ptr_r, wr_ptr_sync, wr_ptr_sync2, wr_b2g_o, wr_g2b_o, prev_wr_addr;

  // Forwarding path and other registers
  logic [width_p-1:0] forward_data_r;
  logic [0:0] empty, full, prev_wr_signal;

  // RAM output
  logic [width_p-1:0] ram_data;

  // Addresses
  logic [depth_log2_p-1:0] rd_addr, wr_addr;
  assign rd_addr = rd_g2b_n[depth_log2_p-1:0]; 
  assign wr_addr = wr_g2b_o[depth_log2_p-1:0];

  // empty full logic
  assign empty = (rd_g2b_o == wr_g2b_o);
  assign full = (rd_g2b_o[depth_log2_p-1:0] == wr_g2b_o[depth_log2_p-1:0]) && (rd_g2b_o[depth_log2_p] != wr_g2b_o[depth_log2_p]);

  // read counter
  counter #(.width_p(depth_log2_p+1)) 
  rd_counter ( 
    .clk_i(pclk_i),
    .reset_i(preset_i),
    .up_i(pready_i && pvalid_o),
    .down_i(1'b0),
    .count_o(rd_ptr_r)
  );

  // read ptr bin 2 gray
  bin2gray #(.width_p(width_p)) read_b2g (
    .bin_i(rd_ptr_r),
    .gray_o(rd_b2g_o)
  );

  // read ptr synchronizers
  dff rd_sync1 (
    .clk_i(pclk_i),
    .reset_i(preset_i),
    .d_i(rd_b2g_o),
    .en_i(1'b1),
    .q_o(rd_ptr_sync)
  );
  dff rd_sync2 (
    .clk_i(pclk_i),
    .reset_i(preset_i),
    .d_i(rd_ptr_sync),
    .en_i(1'b1),
    .q_o(rd_ptr_sync2)
  );

  // read ptr gray 2 binary
  gray2bin #(.width_p(width_p))
  read_g2b (
    .gray_i(rd_ptr_sync2),
    .bin_o(rd_g2b_o)
  );

  // write counter
  counter #(.width_p(depth_log2_p+1)) 
  wr_counter ( 
    .clk_i(cclk_i),
    .reset_i(creset_i),
    .up_i(cready_i && cvalid_o),
    .down_i(1'b0),
    .count_o(wr_ptr_r)
  );

  // write ptr bin 2 gray
  bin2gray #(.width_p(width_p)) 
  write_b2g (
    .bin_i(wr_ptr_r),
    .gray_o(wr_b2g_o)
  );

  // write ptr synchronizers
  dff wr_sync1 (
    .clk_i(cclk_i),
    .reset_i(creset_i),
    .d_i(wr_ptr_r),
    .en_i(1'b1),
    .q_o(wr_ptr_sync)
  );
  dff wr_sync2 (
    .clk_i(cclk_i),
    .reset_i(creset_i),
    .d_i(wr_ptr_sync),
    .en_i(1'b1),
    .q_o(wr_ptr_sync2)
  );

  // wr ptr gray 2 binary
  gray2bin #(.width_p(width_p))
  write_g2b (
    .gray_i(wr_ptr_sync2),
    .bin_o(wr_g2b_o)
  );
  
  always_comb begin
    rd_g2b_n = rd_g2b_o;

    if (pready_i && pvalid_o) begin
      rd_g2b_n = rd_g2b_o + 1'b1;
    end
  end

  // Register updates
  always_ff @(posedge cclk_i) begin
    if (creset_i) begin
      //rd_ptr_n <= '0;
      prev_wr_addr <= '0;
      prev_wr_addr <= '0;
      prev_wr_signal <= '0;
    end else begin
      prev_wr_addr <= wr_g2b_o;
      prev_wr_signal <= cready_i && cvalid_o;
    end
  end
  
  // Instantiate the RAM module
  ram_1r1w_sync #(
    .width_p(width_p),
    .depth_p(depth_p)
  ) ram_inst (
    .clk_i(cclk_i),
    .reset_i(creset_i),
    .wr_valid_i(cready_i && cvalid_o),
    .wr_data_i(cdata_i),
    .wr_addr_i(wr_addr),
    .rd_valid_i(1'b1), 
    .rd_addr_i(rd_addr),
    .rd_data_o(ram_data)
  );

  elastic #(.width_p(width_p))
  forwarding (
    .clk_i(cclk_i),
    .reset_i(creset_i),
    .valid_i(cready_i && cvalid_o),
    .ready_o(),
    .data_i(cdata_i),
    .ready_i(cready_i && cvalid_o),
    .valid_o(),
    .data_o(forward_data_r)
  );
  
  assign pvalid_o = !empty;
  assign cready_o = !full;
  assign pdata_o = ((prev_wr_addr == rd_g2b_o) && prev_wr_signal) ? forward_data_r : ram_data;

endmodule

