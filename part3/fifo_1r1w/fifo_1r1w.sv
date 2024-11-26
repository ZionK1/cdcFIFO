module fifo_1r1w
  #(parameter [31:0] width_p = 8
   // Note: Not depth_p! depth_p should be 1<<depth_log2_p
   ,parameter [31:0] depth_log2_p = 8
   )
  (input [0:0] clk_i
  ,input [0:0] reset_i

  ,input [width_p - 1:0] data_i
  ,input [0:0] valid_i
  ,output [0:0] ready_o 

  ,output [0:0] valid_o 
  ,output [width_p - 1:0] data_o 
  ,input [0:0] ready_i
  );

  localparam depth_p = 1 << depth_log2_p;

  logic [depth_log2_p:0] rd_ptr_r, rd_ptr_n;
  logic [depth_log2_p:0] wr_ptr_r, prev_wr_addr;

  // Forwarding path and other registers
  logic [width_p-1:0] forward_data_r;
  logic [0:0] empty, full, read_op, write_op, prev_wr_signal;

  // RAM output
  logic [width_p-1:0] ram_data;

  // Addresses
  logic [depth_log2_p-1:0] rd_addr, wr_addr;
  assign rd_addr = rd_ptr_n[depth_log2_p-1:0]; 
  assign wr_addr = wr_ptr_r[depth_log2_p-1:0];

  // empty full logic
  assign empty = (rd_ptr_r == wr_ptr_r);
  assign full = (rd_ptr_r[depth_log2_p-1:0] == wr_ptr_r[depth_log2_p-1:0]) && (rd_ptr_r[depth_log2_p] != wr_ptr_r[depth_log2_p]);
  
  // ready valid handshake
  assign read_op = ready_i && valid_o;
  assign write_op = valid_i && ready_o;

  // read counter
  counter #(.width_p(depth_log2_p+1)) 
  rd_counter ( 
    .clk_i(clk_i),
    .reset_i(reset_i),
    .up_i(read_op),
    .down_i(1'b0),
    .count_o(rd_ptr_r)
  );

  // write counter
  counter #(.width_p(depth_log2_p+1)) 
  wr_counter ( 
    .clk_i(clk_i),
    .reset_i(reset_i),
    .up_i(write_op),
    .down_i(1'b0),
    .count_o(wr_ptr_r)
  );
  
  always_comb begin
    rd_ptr_n = rd_ptr_r;

    if (read_op) begin
      rd_ptr_n = rd_ptr_r + 1'b1;
    end
  end

  // Register updates
  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      //rd_ptr_n <= '0;
      prev_wr_addr <= '0;
      prev_wr_addr <= '0;
      prev_wr_signal <= '0;
    end else begin
      prev_wr_addr <= wr_ptr_r;
      prev_wr_signal <= write_op;
    end
  end
  
  // Instantiate the RAM module
  ram_1r1w_sync #(
    .width_p(width_p),
    .depth_p(depth_p)
  ) ram_inst (
    .clk_i(clk_i),
    .reset_i(reset_i),
    .wr_valid_i(write_op),
    .wr_data_i(data_i),
    .wr_addr_i(wr_addr),
    .rd_valid_i(1'b1), 
    .rd_addr_i(rd_addr),
    .rd_data_o(ram_data)
  );

  elastic #(.width_p(width_p))
  forwarding (
    .clk_i(clk_i),
    .reset_i(reset_i),
    .valid_i(write_op),
    .ready_o(),
    .data_i(data_i),
    .ready_i(read_op),
    .valid_o(),
    .data_o(forward_data_r)
  );
  
  assign valid_o = !empty;
  assign ready_o = !full;
  assign data_o = ((prev_wr_addr == rd_ptr_r) && prev_wr_signal) ? forward_data_r : ram_data;

endmodule
