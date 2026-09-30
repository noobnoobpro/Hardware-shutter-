`timescale 1ns / 1ps

module tb_axi_to_gpio;

    // ============================================================
    // CLOCKS
    // ============================================================

    reg clk      = 1'b0;
    reg gpio_clk = 1'b0;

    // AXI clock: 100 MHz
    // period = 10 ns
    always #5 clk = ~clk;

    // GPIO clock: 40 MHz
    // period = 25 ns
    always #12.5 gpio_clk = ~gpio_clk;


    // ============================================================
    // RESET
    // ============================================================

    reg rst_n = 1'b0;


    // ============================================================
    // AXI WRITE SIGNALS
    // ============================================================

    reg  [3:0]  awaddr  = 4'h0;
    reg         awvalid = 1'b0;
    wire        awready;

    reg  [31:0] wdata   = 32'd0;
    reg         wvalid  = 1'b0;
    wire        wready;

    wire        bvalid;
    reg         bready  = 1'b1;


    // ============================================================
    // AXI READ SIGNALS
    // ============================================================

    reg  [3:0]  araddr  = 4'h0;
    reg         arvalid = 1'b0;
    wire        arready;

    wire [31:0] rdata;
    wire        rvalid;
    reg         rready  = 1'b1;


    // ============================================================
    // GPIO OUTPUTS
    // ============================================================

    wire rest;
    wire Shutter;
    wire ExtTPulse;
    wire T0_Sync;
    wire ENPowerPulsing;
    wire CNT_FIFO_EN;
    wire EN_PWR_1v5_A;
    wire EN_PWR_1v5_D;

    wire [63:0] timestamp;


    // ============================================================
    // DUT
    // ============================================================

    axi_to_gpio dut (

        .clk              (clk),
        .rst_n            (rst_n),

        // AXI write
        .awaddr           (awaddr),
        .awvalid          (awvalid),
        .awready          (awready),

        .wdata            (wdata),
        .wvalid           (wvalid),
        .wready           (wready),

        .bvalid           (bvalid),
        .bready           (bready),

        // AXI read
        .araddr           (araddr),
        .arvalid          (arvalid),
        .arready          (arready),

        .rdata            (rdata),
        .rvalid           (rvalid),
        .rready           (rready),

        // GPIO
        .rest             (rest),
        .Shutter          (Shutter),
        .ExtTPulse        (ExtTPulse),
        .T0_Sync          (T0_Sync),
        .ENPowerPulsing   (ENPowerPulsing),
        .CNT_FIFO_EN      (CNT_FIFO_EN),
        .EN_PWR_1v5_A     (EN_PWR_1v5_A),
        .EN_PWR_1v5_D     (EN_PWR_1v5_D),

        .timestamp        (timestamp),

        .gpio_clk         (gpio_clk)
    );


    // ============================================================
    // SIMPLE AXI WRITE TASK
    //
    // NOTE:
    // This deliberately presents AW first, then W.
    // That matches the simplified slave implementation we
    // currently have.
    // ============================================================

    task axi_write;

        input [3:0]  addr;
        input [31:0] value;

        begin

            // --------------------------
            // Address phase
            // --------------------------

            @(negedge clk);

            awaddr  = addr;
            awvalid = 1'b1;

            wait (awready == 1'b1);

            @(negedge clk);

            awvalid = 1'b0;


            // --------------------------
            // Data phase
            // --------------------------

            wdata  = value;
            wvalid = 1'b1;

            wait (wready == 1'b1);

            @(negedge clk);

            wvalid = 1'b0;


            // --------------------------
            // Wait for response
            // --------------------------

            wait (bvalid == 1'b1);

            @(posedge clk);

        end

    endtask


    // ============================================================
    // MAIN TEST
    // ============================================================

    initial begin

        // --------------------------------------------------------
        // Initial values
        // --------------------------------------------------------

        awaddr  = 4'h0;
        awvalid = 1'b0;

        wdata   = 32'd0;
        wvalid  = 1'b0;

        araddr  = 4'h0;
        arvalid = 1'b0;

        bready  = 1'b1;
        rready  = 1'b1;

        rst_n   = 1'b0;


        // ========================================================
        // RESET
        // ========================================================

        $display("");
        $display("========================================");
        $display("RESET");
        $display("========================================");

        #100;

        rst_n = 1'b1;

        #100;


        // ========================================================
        // TEST 1
        // SOFTWARE SHUTTER
        //
        // HW enable = 0
        //
        // Write 0xC2:
        // data[7] = 1
        // data[6] = 1
        // data[1] = 1 -> Shutter HIGH
        // ========================================================

        $display("");
        $display("========================================");
        $display("TEST 1 - SOFTWARE SHUTTER");
        $display("========================================");


        axi_write(
            4'h0,
            32'h000000C2
        );


        // Allow GPIO clock domain to observe data
        #100;


        if (Shutter !== 1'b1) begin

            $display(
                "ERROR: software shutter did not go HIGH"
            );

        end
        else begin

            $display(
                "PASS: software shutter HIGH"
            );

        end


        // Return to 0xC0
        axi_write(
            4'h0,
            32'h000000C0
        );


        #100;


        if (Shutter !== 1'b0) begin

            $display(
                "ERROR: software shutter did not go LOW"
            );

        end
        else begin

            $display(
                "PASS: software shutter LOW"
            );

        end


        // ========================================================
        // TEST 2
        // HARDWARE SHUTTER - WIDTH = 4
        // ========================================================

        $display("");
        $display("========================================");
        $display("TEST 2 - HARDWARE SHUTTER WIDTH = 4");
        $display("========================================");


        // --------------------------------------------------------
        // Write width = 4
        //
        // Register 0x04
        // --------------------------------------------------------

        axi_write(
            4'h4,
            32'd4
        );


        // Give configuration plenty of time to settle
        #100;


        // --------------------------------------------------------
        // Control register:
        //
        // bit 2 = 1 -> HW shutter enable
        // bit 1 = 0 -> reserved
        // bit 0 = 1 -> START
        //
        // binary = 101
        // hex    = 0x5
        // --------------------------------------------------------

        axi_write(
            4'hC,
            32'h00000005
        );


        // Wait until shutter actually starts
        wait (Shutter == 1'b1);


        $display(
            "Hardware shutter WIDTH=4 started at %0t",
            $time
        );


        // Wait until it finishes
        wait (Shutter == 1'b0);


        $display(
            "Hardware shutter WIDTH=4 finished at %0t",
            $time
        );


        #100;


        // ========================================================
        // TEST 3
        // HARDWARE SHUTTER - WIDTH = 8
        // ========================================================

        $display("");
        $display("========================================");
        $display("TEST 3 - HARDWARE SHUTTER WIDTH = 8");
        $display("========================================");


        axi_write(
            4'h4,
            32'd8
        );


        #100;


        // START + HW ENABLE
        axi_write(
            4'hC,
            32'h00000005
        );


        wait (Shutter == 1'b1);


        $display(
            "Hardware shutter WIDTH=8 started at %0t",
            $time
        );


        wait (Shutter == 1'b0);


        $display(
            "Hardware shutter WIDTH=8 finished at %0t",
            $time
        );


        #200;


        // ========================================================
        // END
        // ========================================================

        $display("");
        $display("========================================");
        $display("SIMULATION FINISHED");
        $display("========================================");

        $finish;

    end


endmodule