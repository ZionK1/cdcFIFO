// This is defined for you
`ifndef HEXPATH
 `define HEXPATH ""
`endif
module ram_1r1w_async
  #(parameter [31:0] width_p = 8
  ,parameter [31:0] depth_p = 8
  ,parameter string filename_p = "memory_init_file.bin")
  (input [0:0] clk_i
  ,input [0:0] reset_i

  ,input [0:0] wr_valid_i

  // Fill in the ranges of the busses below
  ,input [width_p-1 : 0] wr_data_i
  ,input [$clog2(depth_p)-1 : 0] wr_addr_i

  ,input [$clog2(depth_p)-1 : 0] rd_addr_i
  ,output [width_p-1 : 0] rd_data_o);

  logic [width_p-1:0] mem [depth_p-1:0];
  initial begin
    // Display depth and width (You will need to match these in your init file)
    $display("%m: depth_p is %d, width_p is %d", depth_p, width_p);

    // wire [bar:0] foo [baz:0];
    //$readmemh({`HEXPATH, filename_p}, /* name of your variable here, e.g. foo */ , 0, /* parameter value here */);
    $readmemh({`HEXPATH, filename_p}, mem , 0, depth_p-1);

    // In order to get the memory contents in iverilog you need to run this for loop during initialization:
    // synopsys translate_off
    for (int i = 0; i < depth_p; i++)
      //$dumpvars(0,/* Your verilog array name here */);
      $dumpvars(0, mem[i]);
    // synopsys translate_on
  end

  // Asynchronous read
  assign rd_data_o = mem[rd_addr_i];

  // Synchronous write
  always_ff @(posedge clk_i) begin
    if (wr_valid_i & !reset_i) begin
      mem[wr_addr_i] <= wr_data_i;
    end
  end
endmodule