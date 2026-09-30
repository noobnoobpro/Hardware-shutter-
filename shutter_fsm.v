`timescale 1ns / 1ps

module shutter_fsm (
    input  wire        clk,
    input  wire        rst_n,

    // IMPORTANT:
    // For this module, trigger is assumed synchronous to clk.
    // If the real trigger is asynchronous, we will add
    // synchronization logic separately.
    input  wire        trigger,

    // Programmable timing values
    input  wire [31:0] delay_cycles,
    input  wire [31:0] shutter_cycles,

    output reg         shutter,
    output reg         busy,

    // Exposed for debugging / ILA later
    output reg  [1:0]  state,
    output reg  [31:0] counter
);

    // ------------------------------------------------------------
    // FSM states
    // ------------------------------------------------------------
    localparam [1:0] IDLE         = 2'd0;
    localparam [1:0] WAIT_DELAY   = 2'd1;
    localparam [1:0] SHUTTER_OPEN = 2'd2;

    // Latch configuration when trigger arrives.
    // This prevents software changing values halfway through a pulse.
    reg [31:0] delay_cfg;
    reg [31:0] width_cfg;

    // ------------------------------------------------------------
    // FSM
    // ------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            state      <= IDLE;
            shutter    <= 1'b0;
            busy       <= 1'b0;
            counter    <= 32'd0;

            delay_cfg  <= 32'd0;
            width_cfg  <= 32'd0;

        end else begin

            case (state)

                // =================================================
                // IDLE
                // =================================================
                IDLE: begin

                    shutter <= 1'b0;
                    busy    <= 1'b0;
                    counter <= 32'd0;

                    if (trigger) begin

                        busy      <= 1'b1;

                        // Capture current configuration
                        delay_cfg <= delay_cycles;
                        width_cfg <= shutter_cycles;

                        // No delay:
                        // open shutter immediately on this clock edge
                        if (delay_cycles == 0) begin

                            shutter <= 1'b1;
                            counter <= 32'd1;
                            state   <= SHUTTER_OPEN;

                        end else begin

                            // Start counting delay cycles
                            counter <= 32'd1;
                            state   <= WAIT_DELAY;

                        end
                    end
                end


                // =================================================
                // WAIT FOR PROGRAMMED DELAY
                // =================================================
                WAIT_DELAY: begin

                    busy    <= 1'b1;
                    shutter <= 1'b0;

                    if (counter >= delay_cfg) begin

                        // Delay completed
                        shutter <= 1'b1;
                        counter <= 32'd1;
                        state   <= SHUTTER_OPEN;

                    end else begin

                        counter <= counter + 1'b1;

                    end
                end


                // =================================================
                // SHUTTER OPEN
                // =================================================
                SHUTTER_OPEN: begin

                    busy    <= 1'b1;
                    shutter <= 1'b1;

                    // Protect against width = 0
                    if (width_cfg == 0) begin

                        shutter <= 1'b0;
                        busy    <= 1'b0;
                        counter <= 32'd0;
                        state   <= IDLE;

                    end

                    else if (counter >= width_cfg) begin

                        // Required shutter width completed
                        shutter <= 1'b0;
                        busy    <= 1'b0;
                        counter <= 32'd0;
                        state   <= IDLE;

                    end else begin

                        counter <= counter + 1'b1;

                    end
                end


                // =================================================
                // SAFETY
                // =================================================
                default: begin

                    state   <= IDLE;
                    shutter <= 1'b0;
                    busy    <= 1'b0;
                    counter <= 32'd0;

                end

            endcase
        end
    end

endmodule