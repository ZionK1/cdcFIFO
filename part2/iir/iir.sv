module iir
  #(
   // This is here to help, but we won't change it.
   parameter width_p = 10
   )
  (input [0:0] clk_i
  ,input [0:0] reset_i

  ,input [0:0] valid_i
  ,input [width_p - 1:0] data_i
  ,output [0:0] ready_o

  ,output [0:0] valid_o
  ,output [width_p - 1:0] data_o
  ,input [0:0] ready_i
  );

  //  wire [/* TODO: Bits, with more fractional after multiplication */] data_lo;
  
  //  wire [/* TODO: Some integer bits, some fractional bits */] sub = (data_li - data_lo[/* TODO: Some integer bits, some fractional bits */]);

  //  wire [/* TODO: Some integer bits, some fractional bits */] b = {/* TODO: Fixed point value (plus some zero integer bits */};
  //  wire [/* TODO: Bits, with more fractional after multiplication */] mul = $signed(sub) * $signed(b);

  //  wire [/* TODO: Bits, with more fractional after multiplication and addition*/] acc = data_lo + mul;

  //  wire [/* TODO: Some integer bits, some fractional bits */] data_li;

  //  assign data_li = {/*TODO: Zero Pad for fractional bits */};

  //  assign data_o = data_lo[/*TODO: Lop off fractional bits*/];

  // take integer bits of data_i and pad 0s for fractional bits
  //wire [9:-17] data_li;
  wire [width_p - 1:-(27 - width_p)] data_li;
  //assign data_li = {data_i, 17'b0};
  assign data_li = {data_i, {(27 - width_p){1'b0}}};
  
  //wire [9:-22] data_lo;
  wire [width_p - 1:-(32 - width_p)] data_lo;

  // subtract signed new data_li with prev data_lo (both 9:-16)
  // wire [9:-17] sub = ($signed(data_li) - data_lo[9:-17]);
  wire [width_p - 1:-(27 - width_p)] sub = ($signed(data_li) - data_lo[9:-17]);

  // pad signed bit then 5 bits for 0.921875
  wire [0:-5] b = {1'b0, 1'b1, 1'b1, 1'b0, 1'b1, 1'b1};

  // multiplying sub and b = [9 + 0, -17 + -5] = [9:-22]
  // wire [9:-22] mul = $signed(sub) * $signed(b);
  wire [width_p - 1:-(32 - width_p)] mul = $signed(sub) * $signed(b);

  // acc: prev data + new product
  wire [width_p - 1:-(32 - width_p)] acc = data_lo + mul;

  elastic
    #(.width_p(32)
     ,.datapath_reset_p(1'b1)
     ,.datapath_gate_p(1'b1))
  elastic_inst
    (.clk_i                            (clk_i)
    ,.reset_i                          (reset_i)

    ,.data_i                           (acc)
    ,.valid_i                          (valid_i)
    ,.ready_o                          (ready_o)

    ,.valid_o                          (valid_o)
    ,.data_o                           (data_lo)
    ,.ready_i                          (ready_i));

  // lop off fractional bits here
  assign data_o = data_lo[width_p-1:0];

endmodule
