`timescale 1ns / 1ps

module tb_clk_wiz;

    reg clk_in1 = 0;
    reg reset = 0;

    reg psclk = 0;
    reg psen = 0;
    reg psincdec = 0;

    wire clk_out1;
    wire clk_out2;
    wire locked;
    wire psdone;


    clk_wiz_0 dut (
        .clk_out1   (clk_out1),
        .clk_out2   (clk_out2),

        .reset      (reset),
        .locked     (locked),
        .clk_in1    (clk_in1),

        .psclk      (psclk),
        .psen       (psen),
        .psincdec   (psincdec),
        .psdone     (psdone)
    );

task phase_step;
begin
    // wait for no previous completion to be still active 
    wait (psdone == 1'b0);

    // Request one phase shift
    @(negedge psclk);
    psen = 1'b1;

    @(negedge psclk);
    psen = 1'b0;

    // Wait for current operation to complete
    @(posedge psdone);
    // Wait for current operation to complete
    @(negedge psdone);

end
endtask
    // 100 MHz input clock
    always #5 clk_in1 = ~clk_in1;

    // 100 MHz phase-control clock
    always #5 psclk = ~psclk;


    initial begin

        psen     = 0;
        psincdec = 1;

        // Wait until MMCM has locked
        wait(locked == 1);




   // Move phase forward several steps
    phase_step();
    phase_step();
    phase_step();
    phase_step();
    phase_step();
    phase_step();
    phase_step();
    phase_step();
    phase_step();
    phase_step();
    psincdec = 0;
    phase_step();
    phase_step();
    phase_step();
    phase_step();
    phase_step();
    phase_step();
    phase_step();
    phase_step();
    phase_step();
    phase_step();

    #500;

        $finish;

    end

endmodule