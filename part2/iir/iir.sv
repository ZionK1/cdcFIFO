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

   wire [/* TODO: Bits, with more fractional after multiplication */] data_lo;
   wire [/* TODO: Some integer bits, some fractional bits */] sub = (data_li - data_lo[/* TODO: Some integer bits, some fractional bits */]);

   wire [/* TODO: Some integer bits, some fractional bits */] b = {/* TODO: Fixed point value (plus some zero integer bits */};
   wire [/* TODO: Bits, with more fractional after multiplication */] mul = $signed(sub) * $signed(b);

   wire [/* TODO: Bits, with more fractional after multiplication and addition*/] acc = data_lo + mul;

   wire [/* TODO: Some integer bits, some fractional bits */] data_li;

   assign data_li = {/*TODO: Zero Pad for fractional bits */};

   assign data_o = data_lo[/*TODO: Lop off fractional bits*/];

   elastic
     #(.width_p(/* TODO: Bits, with more fractional after multiplication*/))
   elastic_inst
     (.clk_i                            (clk_i)
     ,.reset_i                          (reset_i)

     ,.data_i                           (/* TODO: Bits, with more fractional after multiplication*/])
     ,.valid_i                          (valid_i)
     ,.ready_o                          (ready_o)

     ,.valid_o                          (valid_o)
     ,.data_o                           (data_lo)
     ,.ready_i                          (ready_i));

endmodule
