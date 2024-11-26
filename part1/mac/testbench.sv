`timescale 1ns/1ps
`define START_TESTBENCH error_o = 0; pass_o = 0; #10;
`define FINISH_WITH_FAIL error_o = 1; pass_o = 0; #10; $finish();
`define FINISH_WITH_PASS pass_o = 1; error_o = 0; #10; $finish();
module testbench
  // You don't usually have ports in a testbench, but we need these to
  // signal to cocotb/gradescope that the testbench has passed, or failed.
  (output logic error_o = 1'bx
   ,output logic pass_o = 1'bx);

   // You can use these to parameterize your own module.
   // We need two integer bits. One for encoding 1/0, and one sign bit.
   localparam int_in_lp = 2;
   localparam frac_in_lp = 14;

   localparam int_out_lp = 10;
   localparam frac_out_lp = 22;
   
   wire       clk_i;
   bit        reset_i;
   wire       _reset_i;

   // Use reset_il to set reset from procedural blocks.
   bit        reset_il;
   assign reset_i = _reset_i | reset_il;

   logic [int_in_lp - 1 : -frac_in_lp] a_il;
   logic [int_in_lp - 1 : -frac_in_lp] b_il;

   // I'm using bit here to get a 0/1 type
   bit                                 valid_il;
   wire                                ready_o;

   wire signed  [int_out_lp - 1 : -frac_out_lp] data_o;
   wire                                 valid_o;
   bit                                  ready_il;

   nonsynth_clock_gen
     #(.cycle_time_p(10))
   cg
     (.clk_o(clk_i));

   nonsynth_reset_gen
     #(.reset_cycles_lo_p(0)
       ,.reset_cycles_hi_p(10))
   rg
     (.clk_i(clk_i)
      ,.async_reset_o(_reset_i));

   mac
     #(.int_in_lp(int_in_lp)
       ,.frac_in_lp(frac_in_lp)
       ,.int_out_lp(int_out_lp)
       ,.frac_out_lp(frac_out_lp)
       )
   dut
     (.clk_i(clk_i)
      ,.reset_i(reset_i)
      ,.a_i(a_il)
      ,.b_i(b_il)
      ,.valid_i(valid_il)
      ,.ready_o(ready_o)

      ,.valid_o(valid_o)
      ,.data_o(data_o)
      ,.ready_i(ready_il)
      );

   // Track how many handshakes have occured at the input interface.
   int                                  wr_count;
   always_ff @(posedge clk_i) begin
      // Only reset wr_count at the very start of simulation
      if(_reset_i)
        wr_count <= 0;
      else 
        wr_count <= wr_count + (valid_il & (ready_o === 1'b1));
   end

   // Track how many handshakes have occured at the output interface
   int rd_count;
   always_ff @(posedge clk_i) begin
      if(_reset_i)
        rd_count <= 0;
      else 
        rd_count <= rd_count + (ready_il & (valid_o === 1'b1));
   end

   // Use done to tell the "tracker" we're done.
   bit                                 input_done = 0;
   always @(posedge clk_i) begin
      // If the input generator is done and the write count is equal
      // to the read count, then terminate the simulator with a pass.
      if(input_done && (rd_count == wr_count)) begin
         `FINISH_WITH_PASS;
      end
   end

   // Input Generator
   // Since it's unsafe to read outputs of a module in an initial
   // block, sanitize the input/write handshake by capturing it in a
   // signal we control.
   bit consume_success;
   always_ff @(posedge clk_i) begin
      consume_success <= valid_il & (ready_o === 1'b1);
   end   

   // Input Interface Watchdog Timer
   int wr_timeout;
   always @(posedge clk_i) begin
      if(reset_i || (valid_il & (ready_o === 1))) begin
         wr_timeout <= 0;
      end else if(wr_timeout > 10) begin
         $error("Timeout on input interface. valid_i was high for 10 cycles with no response.");
         `FINISH_WITH_FAIL;
      end else if(valid_il & (ready_o !== 1) & (a_q.size() == 0)) begin
         wr_timeout <= wr_timeout + 1;
      end
   end

   int itervar;
   initial begin
      `START_TESTBENCH;
      // Set input signals to zeros to ensure that dut state is not
      // polluted by x's
      valid_il = 1'b0;
      reset_il = 1'b0;
      a_il = '0;
      b_il = '0;
      // We'll use this later
      itervar = 0;

      @(negedge reset_i);

      // Wait a few clock cycles
      @(negedge clk_i);

      $display();
      $display("Input Generator, Start.");
      
      // This is the input stimulus generator. Since this isn't a
      // "full testbench", we don't check full/empty, we just check
      // for functionality.

      // Input constant "a" numbers while sweeping the range of b
      a_il = '0;
      b_il = '0;
      a_il[0] = 1;
      b_il[0] = 1;
      itervar = 0;
      do begin
         // Randomly decide when to transmit data
         valid_il = ($urandom_range(0, 1) == 1);

         // If we decided to transmit data, iterate until it was read
         // into the DUT.

         // consume_success is set in an always_ff block and
         // indicates a successfull input handshake on the LAST
         // posedge.
         do begin
            @(negedge clk_i);
         end while((valid_il == 1'b1) && (consume_success == 1'b0));

         if(consume_success == 1) begin
            itervar += 1;
            // Produce an "A" tone.
            b_il = b_il >> 1;
            $display("On B-sweep Data iteration: %d. b_il: %b", itervar, b_il);
         end

         valid_il = 0;
         @(negedge clk_i);
      end while(b_il != '0); // do begin

      // Wait for DUT to flush.
      while(rd_count != wr_count) begin
         @(negedge clk_i);
      end

      reset_il = 1'b1;
      // Wait a few clock cycles
      repeat(2) @(negedge clk_i);

      reset_il = 1'b0;
      repeat(2) @(negedge clk_i);
      
      // Input constant "b" numbers while sweeping the range of a
      a_il = '0;
      b_il = '0;
      a_il[0] = 1;
      b_il[0] = 1;
      itervar = 0;
      do begin
         // Randomly decide when to transmit data
         valid_il = ($urandom_range(0, 1) == 1);

         // If we decided to transmit data, iterate until it was read
         // into the DUT.

         // consume_success is set in an always_ff block and
         // indicates a successfull input handshake on the LAST
         // posedge.
         do begin
            @(negedge clk_i);
            // Wait until data was consumed to proceed
         end while((valid_il == 1'b1) && (consume_success == 1'b0));

         if(consume_success == 1) begin
            itervar += 1;
            // Produce an "A" tone.
            a_il = a_il >> 1;
            $display("On A-sweep Data iteration: %d. a_il: %b", itervar, a_il);
         end

         valid_il = 0;
         @(negedge clk_i);
      end while(a_il != '0);

      // Wait for DUT to flush.
      while(rd_count != wr_count) begin
         @(negedge clk_i);
      end

      reset_il = 1'b1;
      // Wait a few clock cycles
      repeat(2) @(negedge clk_i);

      reset_il = 1'b0;
      repeat(2) @(negedge clk_i);
      
      // One really useful mathematical trick that you can apply is to
      // "integrate" sine over a range of 2*pi. It should always be
      // approximately zero. Do this by setting b to 1, and setting a
      // to a function of sin.
      a_il = '0;
      b_il[0] = 1;
      itervar = 0;
      do begin
         // Randomly decide when to transmit data
         valid_il = ($urandom_range(0, 1) == 1);

         // If we decided to transmit data, iterate until it was read
         // into the DUT.

         // consume_success is set in an always_ff block and
         // indicates a successfull input handshake on the LAST
         // posedge.
         do begin
            @(negedge clk_i);
            // Wait until data was consumed to proceed
         end while((valid_il == 1'b1) && (consume_success == 1'b0));

         // If the last data was consumed
         if(consume_success == 1) begin
            itervar += 1;
            // Produce an "A" tone.
            a_il = $sin(440 * (itervar * 2 * 3.141592) / 44000) * (1 << frac_in_lp);
            $display("On Sinusoid iteration: %d. a_il: %f, %b", itervar, (1.0 * $signed(a_il))/(1 << frac_in_lp), a_il);
         end
         
         valid_il = 0;
         @(negedge clk_i);
      end while(itervar != 100);

      // Wait for DUT to flush.
      while(rd_count != wr_count) begin
         @(negedge clk_i);
      end

      // This will eventually terminate simulation.
      input_done = 1;
   end


   // Output stimulus generator

   // Since it's unsafe to read outputs of a module in an initial
   // block, sanitize the output/read handshake by capturing it in a
   // signal we control.
   bit produce_success;
   always_ff @(posedge clk_i) begin
      produce_success <= ready_il & (valid_o === 1'b1);
   end

   // Output Interface Watchdog Timer
   int rd_timeout;
   always @(posedge clk_i) begin
      if(reset_i || (ready_il & (valid_o === 1))) begin
         rd_timeout <= 0;
      end else if(rd_timeout > 10) begin
         $error("Timeout on output interface. ready_i was high for 10 cycles with no response.");
         `FINISH_WITH_FAIL;
      end else if(ready_il & (valid_o !== 1) & (a_q.size() > 0)) begin
         // If the TB is ready, and valid isn't going high, and there's data "in the model"
         rd_timeout <= rd_timeout + 1;
      end
   end

   // Procedural code for generating output stimulus.
   initial begin
      // Set input signals to zeros to ensure that dut state is not
      // polluted by x's
      ready_il = 1'b0;

      @(negedge reset_i);

      // Wait a few clock cycles
      repeat(2) @(negedge clk_i);

      $display();
      $display("Output Generator, Start.");

      // This is the output stimulus generator. Since this isn't a
      // "full testbench", we don't check full/empty, we just check
      // for functionality.
      forever begin
         // Randomly decide to read data from the DUT
         ready_il = ($urandom_range(0, 1) == 1);

         // If we decided to read data from the DUT, iterate until
         // there is valid data.

         // produce_success is set in an always_ff block and indicates
         // a successfull output handshake on the LAST posedge.
         do begin
            @(negedge clk_i);
            // Wait until data was consumed to proceed
         end while((ready_il == 1'b1) && (produce_success == 1'b0));
         
         // Set ready_il to 0 and wait another clock cycle to try again
         ready_il = 0;
         @(negedge clk_i);
      end
      
      `FINISH_WITH_FAIL;
   end


   // This is our behavioral model. It is modeled with two queues for
   // tracking which data has been fed into the mac.

   // Model state
   logic signed [int_out_lp - 1 : -frac_out_lp]   acc_r;
   logic [int_in_lp - 1 : -frac_out_lp]    a_q [$];
   logic [int_in_lp - 1 : -frac_out_lp]    b_q [$];

   // Internal temp varaiables
   logic signed [int_in_lp - 1 : -frac_in_lp]     a_tl;
   logic signed [int_in_lp - 1 : -frac_in_lp]     b_tl;
   logic signed [(2 * int_in_lp) - 1 : -(2 * frac_in_lp)] mul_tl;

   // Model "Ingestor"/Consumer
   always @(posedge clk_i) begin
      if(reset_i) begin
         a_q.delete();
         b_q.delete();
      end else if ($isunknown(ready_o)) begin
         // Check for resolvable ready_o (we control valid_il)
         $error("DUT produced unresolvable value on ready_o");
         `FINISH_WITH_FAIL;
      end else if (valid_il & ready_o) begin
         // If the core has ingested data, ingest it into our model.
         a_q.push_back(a_il);
         b_q.push_back(b_il);
      end
   end

   // Model "Output"/Producer Checker
   always @(posedge clk_i) begin
      if(reset_i) begin
         acc_r = 0;
      end else if ($isunknown(valid_o)) begin
         // Check for resolvable valid_o (we control ready_il)
         $error("DUT produced unresolvable value on valid_o");
         `FINISH_WITH_FAIL;
      end else if (valid_o & ready_il) begin
         // If the core has produced data, produce it out of our model
         // Fail, if the model has no data to produce.
         if ((a_q.size() == 0) || (b_q.size() == 0)) begin
            $error("DUT produced output data (valid_o & ready_i == 1), but no data available in model");
            `FINISH_WITH_FAIL;
         end else if($isunknown(data_o))begin
            // Check data_o, ensure resolvability)
            $error("DUT produced unresolvable data_o.");
            `FINISH_WITH_FAIL;
         end else begin
            // Yes, I am using = inside of a always_ff block.
            // 1. It is not synthesizable.
            // 2. It is useful for doing checking logic (like here).
            // 3. These signals are not used anywhere else.
            a_tl = a_q.pop_front();
            b_tl = b_q.pop_front();
            mul_tl = a_tl * b_tl;
            acc_r += mul_tl;
            
            if(acc_r !== data_o) begin
               $error("DUT output data does not match model data.\
                         DUT data_o: %f (%b). Model output: %f (%b).",
                      1.0 * data_o / (1 << frac_out_lp), data_o,
                      1.0 * acc_r  / (1 << frac_out_lp), acc_r);
               `FINISH_WITH_FAIL;
            end else begin
               // You can comment this out for less verbosity.
               $display("DUT data_o: %f (%b). Model output: %f (%b).",
                        1.0 * data_o / (1 << frac_out_lp), data_o,
                        1.0 * acc_r  / (1 << frac_out_lp), acc_r);
            end

         end
      end
   end // always @ (posedge clk_i)
   
   // This block executes after $finish() has been called.
   final begin
      $display("Simulation time is %t", $time);
      if(error_o) begin
	 $display("\033[0;31m    ______                    \033[0m");
	 $display("\033[0;31m   / ____/_____________  _____\033[0m");
	 $display("\033[0;31m  / __/ / ___/ ___/ __ \\/ ___/\033[0m");
	 $display("\033[0;31m / /___/ /  / /  / /_/ / /    \033[0m");
	 $display("\033[0;31m/_____/_/  /_/   \\____/_/     \033[0m");
	 $display("Simulation Failed");
      end else begin
	 $display("\033[0;32m    ____  ___   __________\033[0m");
	 $display("\033[0;32m   / __ \\/   | / ___/ ___/\033[0m");
	 $display("\033[0;32m  / /_/ / /| | \\__ \\\__ \ \033[0m");
	 $display("\033[0;32m / ____/ ___ |___/ /__/ / \033[0m");
	 $display("\033[0;32m/_/   /_/  |_/____/____/  \033[0m");
	 $display();
	 $display("Simulation Succeeded!");
      end
   end

endmodule
