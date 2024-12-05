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

  logic [depth_log2_p:0] rd_ptr_n, rd_ptr_r, rd_ptr_delay, rd_ptr_sync1, rd_ptr_sync2, rd_b2g_o, rd_g2b_o;
  logic [depth_log2_p:0] wr_ptr_n, wr_ptr_r, wr_ptr_delay, wr_ptr_sync1, wr_ptr_sync2, wr_b2g_o, wr_g2b_o;

  // Forwarding path and other registers
  logic [0:0] empty, full;

  // RAM output
  logic [width_p-1:0] ram_data;

  // Addresses
  logic [depth_log2_p-1:0] rd_addr, wr_addr;
  assign rd_addr = rd_ptr_n[depth_log2_p-1:0]; 
  assign wr_addr = wr_ptr_r[depth_log2_p-1:0];

  // empty uses wr_g2b_o and rd_ptr_r
  assign empty = (rd_ptr_r == wr_g2b_o);

  // full uses rd_g2b_o and wr_ptr_r
  assign full = (rd_g2b_o[depth_log2_p-1:0] == wr_ptr_r[depth_log2_p-1:0]) && (rd_g2b_o[depth_log2_p] != wr_ptr_r[depth_log2_p]);

  // read counter
  always_ff @(posedge cclk_i) begin
    if (creset_i) begin
      wr_ptr_r <= '0;
    end else begin
      wr_ptr_r <= wr_ptr_n;
    end
  end

  always_ff @(posedge pclk_i) begin
    if (preset_i) begin
      rd_ptr_r <= '0;
    end else begin
      rd_ptr_r <= rd_ptr_n;
    end
  end

  always_comb begin
    wr_ptr_n = wr_ptr_r;
    rd_ptr_n = rd_ptr_r;

    if (cvalid_i && cready_o) begin
      wr_ptr_n = wr_ptr_r + 1;
    end

    if (pready_i && pvalid_o) begin
      rd_ptr_n = rd_ptr_r + 1;
    end
  end
  /*
  counter #(.width_p(depth_log2_p+1)) 
  rd_counter ( 
    .clk_i(pclk_i),
    .reset_i(preset_i),
    .up_i(pready_i & pvalid_o & !empty),
    .down_i(1'b0),
    .count_o(rd_ptr_n)
  ); */

  // read ptr bin 2 gray
  bin2gray #(.width_p(depth_log2_p+1)) read_b2g (
    .bin_i(rd_ptr_r),
    .gray_o(rd_b2g_o)
  );

  // read ptr synchronizers
  /*
  generate
    for (genvar i = 0; i < (depth_log2_p+1); i++) begin : rd_sync
      dff rd_sync1 (
        .clk_i(cclk_i),
        .reset_i(preset_i),
        .d_i(rd_b2g_o[i]),
        .en_i(1'b1),
        .q_o(rd_ptr_sync1[i])
      );
      dff rd_sync2 (
        .clk_i(cclk_i),
        .reset_i(preset_i),
        .d_i(rd_ptr_sync1[i]),
        .en_i(1'b1),
        .q_o(rd_ptr_sync2[i])
      );
    end
  endgenerate */
  /*
  always_ff @(posedge pclk_i) begin
    rd_ptr_delay <= rd_b2g_o;
  end */

  always_ff @(posedge cclk_i) begin
    if (creset_i) begin
      rd_ptr_sync1 <= '0;
    end else begin
      rd_ptr_sync1 <= rd_b2g_o;
    end
  end

  always_ff @(posedge cclk_i) begin
    if (creset_i) begin
      rd_ptr_sync2 <= '0;
    end else begin
      rd_ptr_sync2 <= rd_ptr_sync1;
    end
  end

  // read ptr gray 2 binary
  gray2bin #(.width_p(depth_log2_p+1))
  read_g2b (
    .gray_i(rd_ptr_sync2),
    .bin_o(rd_g2b_o)
  );

  // write counter
  /*
  counter #(.width_p(depth_log2_p+1)) 
  wr_counter ( 
    .clk_i(cclk_i),
    .reset_i(creset_i),
    .up_i(cvalid_i & cready_o & !full),
    .down_i(1'b0),
    .count_o(wr_ptr_n)
  ); */

  // write ptr bin 2 gray
  bin2gray #(.width_p(depth_log2_p+1)) 
  write_b2g (
    .bin_i(wr_ptr_r),
    .gray_o(wr_b2g_o)
  );

  // write ptr synchronizers
  /*
  generate
    for (genvar i = 0; i < (depth_log2_p+1); i++) begin : wr_sync
      dff wr_sync1 (
        .clk_i(pclk_i),
        .reset_i(creset_i),
        .d_i(wr_b2g_o[i]),
        .en_i(1'b1),
        .q_o(wr_ptr_sync1[i])
      );
      dff wr_sync2 (
        .clk_i(pclk_i),
        .reset_i(creset_i),
        .d_i(wr_ptr_sync1[i]),
        .en_i(1'b1),
        .q_o(wr_ptr_sync2[i])
      );
    end
  endgenerate */
  
  /*
  always_ff @(posedge cclk_i) begin
    wr_ptr_delay <= wr_b2g_o;
  end */

  always_ff @(posedge pclk_i) begin
    if (preset_i) begin
      wr_ptr_sync1 <= '0;
    end else begin
      wr_ptr_sync1 <= wr_b2g_o;
    end
  end

  always_ff @(posedge pclk_i) begin
    if (preset_i) begin
      wr_ptr_sync2 <= '0;
    end else begin
      wr_ptr_sync2 <= wr_ptr_sync1;
    end
  end

  // wr ptr gray 2 binary
  gray2bin #(.width_p(depth_log2_p+1))
  write_g2b (
    .gray_i(wr_ptr_sync2),
    .bin_o(wr_g2b_o)
  );
  
  // Instantiate sync RAM
  ram_1r1w_sync #(
    .width_p(width_p),
    .depth_p(depth_p)
  ) ram_inst (
    .cclk_i(cclk_i),
    .pclk_i(pclk_i),
    .reset_i(1'b0),
    .wr_valid_i(cvalid_i & cready_o),
    .wr_data_i(cdata_i),
    .wr_addr_i(wr_addr[depth_log2_p-1:0]),
    .rd_valid_i(1'b1), 
    .rd_addr_i(rd_addr[depth_log2_p-1:0]),
    .rd_data_o(ram_data)
  ); 
 
  /*
  // Instantiate async RAM
  ram_1r1w_async #(
    .width_p(width_p),
    .depth_p(depth_p),
    .filename_p()
  ) ram_inst (
    .clk_i(cclk_i),
    .reset_i(creset_i),
    .wr_valid_i(cvalid_i & cready_o & !full),
    .wr_data_i(cdata_i),
    .wr_addr_i(wr_addr[depth_log2_p-1:0]),
    .rd_addr_i(rd_addr[depth_log2_p-1:0]),
    .rd_data_o(ram_data)
  ); */

  /*
  inelastic #(.width_p(width_p))
  inelastic_inst (
    .clk_i(cclk_i),
    .reset_i(creset_i),
    .en_i(1'b1)
  ); */
  
  assign pvalid_o = !empty;
  assign cready_o = !full;
  assign pdata_o = ram_data;

endmodule

