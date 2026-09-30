`timescale 1ns / 1ps

module tb_shutter_fsm;

    reg clk;
    reg rst_n;
    reg trigger;

    reg [31:0] delay_cycles;
    reg [31:0] shutter_cycles;

    wire shutter;
    wire busy;
    wire [1:0] state;
    wire [31:0] counter;

    localparam [1:0] IDLE         = 2'd0;
    localparam [1:0] WAIT_DELAY   = 2'd1;
    localparam [1:0] SHUTTER_OPEN = 2'd2;

    integer errors;

    time shutter_start;
    time shutter_end;


    // ============================================================
    // DUT
    // ============================================================

    shutter_fsm dut (
        .clk(clk),
        .rst_n(rst_n),
        .trigger(trigger),

        .delay_cycles(delay_cycles),
        .shutter_cycles(shutter_cycles),

        .shutter(shutter),
        .busy(busy),
        .state(state),
        .counter(counter)
    );


    // ============================================================
    // 100 MHz CLOCK
    //
    // Period = 10 ns
    // Half period = 5 ns
    // ============================================================

    initial begin
        clk = 1'b0;

        forever begin
            #5 clk = ~clk;
        end
    end


    // ============================================================
    // WAVEFORM DUMP
    // ============================================================

    initial begin

        $dumpfile("shutter_fsm.vcd");

        $dumpvars(0, tb_shutter_fsm);

    end


    // ============================================================
    // HELPER TASK
    //
    // Generate trigger for exactly one clock cycle.
    // ============================================================

    task send_trigger;

        begin

            @(negedge clk);

            trigger = 1'b1;

            @(negedge clk);

            trigger = 1'b0;

        end

    endtask


    // ============================================================
    // MAIN TEST
    // ============================================================

    initial begin

        errors = 0;

        rst_n          = 1'b0;
        trigger        = 1'b0;

        delay_cycles   = 32'd0;
        shutter_cycles = 32'd5;


        // --------------------------------------------------------
        // RESET
        // --------------------------------------------------------

        repeat (3)
            @(posedge clk);

        @(negedge clk);

        rst_n = 1'b1;


        // ========================================================
        // TEST 1
        //
        // delay = 0
        // width = 5 cycles
        //
        // Expected:
        //
        // shutter opens immediately when trigger is sampled.
        //
        // 100 MHz:
        // 5 cycles = 50 ns
        // ========================================================

        $display("");
        $display("========================================");
        $display("TEST 1: ZERO DELAY");
        $display("========================================");

        delay_cycles   = 32'd0;
        shutter_cycles = 32'd5;


        fork

            send_trigger();

            begin

                @(posedge trigger);

                // Wait for next clock edge where trigger is sampled
                @(posedge clk);

                #1;

                if (shutter !== 1'b1) begin

                    $display(
                        "ERROR: shutter did not open immediately"
                    );

                    errors = errors + 1;

                end else begin

                    $display(
                        "PASS: shutter opened on trigger clock edge"
                    );

                end


                if (state !== SHUTTER_OPEN) begin

                    $display(
                        "ERROR: FSM not in SHUTTER_OPEN state"
                    );

                    errors = errors + 1;

                end


                shutter_start = $time;


                while (shutter == 1'b1) begin

                    @(posedge clk);

                    #1;

                end


                shutter_end = $time;


                if ((shutter_end - shutter_start) != 50) begin

                    $display(
                        "ERROR: shutter width = %0t ns, expected 50 ns",
                        shutter_end - shutter_start
                    );

                    errors = errors + 1;

                end else begin

                    $display(
                        "PASS: shutter width = %0t ns",
                        shutter_end - shutter_start
                    );

                end

            end

        join


        repeat (3)
            @(posedge clk);


        // ========================================================
        // TEST 2
        //
        // delay = 1 cycle
        // width = 3 cycles
        //
        // Expected:
        //
        // shutter opens exactly 10 ns later.
        // ========================================================

        $display("");
        $display("========================================");
        $display("TEST 2: ONE CLOCK DELAY");
        $display("========================================");

        delay_cycles   = 32'd1;
        shutter_cycles = 32'd3;


        fork

            send_trigger();

            begin

                @(posedge trigger);

                @(posedge clk);

                #1;


                // After trigger is sampled:
                // should be waiting for delay
                if (state !== WAIT_DELAY) begin

                    $display(
                        "ERROR: FSM did not enter WAIT_DELAY"
                    );

                    errors = errors + 1;

                end else begin

                    $display(
                        "PASS: FSM entered WAIT_DELAY"
                    );

                end


                if (shutter !== 1'b0) begin

                    $display(
                        "ERROR: shutter opened too early"
                    );

                    errors = errors + 1;

                end


                // One more 100 MHz clock
                @(posedge clk);

                #1;


                if (shutter !== 1'b1) begin

                    $display(
                        "ERROR: shutter did not open after 1 cycle"
                    );

                    errors = errors + 1;

                end else begin

                    $display(
                        "PASS: shutter opened exactly 1 clock later"
                    );

                end


                shutter_start = $time;


                while (shutter == 1'b1) begin

                    @(posedge clk);

                    #1;

                end


                shutter_end = $time;


                if ((shutter_end - shutter_start) != 30) begin

                    $display(
                        "ERROR: shutter width = %0t ns, expected 30 ns",
                        shutter_end - shutter_start
                    );

                    errors = errors + 1;

                end else begin

                    $display(
                        "PASS: shutter width = %0t ns",
                        shutter_end - shutter_start
                    );

                end

            end

        join


        repeat (3)
            @(posedge clk);


        // ========================================================
        // TEST 3
        //
        // RESET WHILE SHUTTER IS OPEN
        //
        // Safety test.
        // ========================================================

        $display("");
        $display("========================================");
        $display("TEST 3: RESET DURING SHUTTER OPEN");
        $display("========================================");


        delay_cycles   = 32'd0;
        shutter_cycles = 32'd20;


        send_trigger();


        wait (shutter == 1'b1);


        repeat (2)
            @(posedge clk);


        rst_n = 1'b0;


        #1;


        if (shutter !== 1'b0) begin

            $display(
                "ERROR: shutter did not close during reset"
            );

            errors = errors + 1;

        end else begin

            $display(
                "PASS: reset immediately forced shutter LOW"
            );

        end


        if (state !== IDLE) begin

            $display(
                "ERROR: FSM not returned to IDLE during reset"
            );

            errors = errors + 1;

        end


        repeat (2)
            @(posedge clk);


        rst_n = 1'b1;


        // ========================================================
        // FINAL RESULT
        // ========================================================

        repeat (5)
            @(posedge clk);


        $display("");
        $display("========================================");

        if (errors == 0) begin

            $display("ALL SHUTTER FSM TESTS PASSED");

        end else begin

            $display(
                "TEST FAILED: %0d error(s)",
                errors
            );

        end

        $display("========================================");
        $display("");


        $finish;

    end

endmodule