// Convert MIG's existing averaged XADC output; DDR3 owns the only sensor.
module k2_temperature #(
    parameter integer POLL_CYCLES = 100_000_000,
    parameter integer TIMEOUT_CYCLES = 1_000_000
) (
    input wire clk_i, reset_i,
    input wire [11:0] raw_i,
    input wire available_i, heartbeat_i,
    output logic valid_o,
    output logic signed [9:0] degrees_o
);
    logic [31:0] poll_count, timeout_count;
    logic heartbeat, alive;
    logic [11:0] sample;
    logic signed [31:0] scaled;
    typedef enum logic [1:0] {IDLE, CONVERT, PUBLISH} state_t;
    state_t state;
    // 8064/65536 approximates 503.975/4096 to <0.026 C over all ADC codes.
    // Shift/subtract avoids a DSP or divider. Round to nearest whole degree.
    wire signed [31:0] code = $signed({20'b0, sample});
    wire signed [31:0] rounded = scaled >>> 16;
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            poll_count <= POLL_CYCLES-1; timeout_count <= 0;
            valid_o <= 0; degrees_o <= 0; heartbeat <= 0; alive <= 0;
            sample <= 0; scaled <= 0; state <= IDLE;
        end else begin
            heartbeat <= heartbeat_i;
            if (heartbeat_i != heartbeat) begin
                timeout_count <= TIMEOUT_CYCLES-1; alive <= 1;
            end else if (timeout_count != 0) timeout_count <= timeout_count - 1'b1;
            else alive <= 0;
            if (poll_count != 0) poll_count <= poll_count - 1'b1;
            case (state)
                IDLE: if (poll_count == 0) begin
                    poll_count <= POLL_CYCLES-1;
                    sample <= raw_i; state <= CONVERT;
                end
                CONVERT: begin
                    scaled <= (code <<< 13) - (code <<< 7) - 32'sd17901158 + 32'sd32768;
                    state <= PUBLISH;
                end
                PUBLISH: begin
                    degrees_o <= rounded[9:0];
                    // Reject uninitialized, implausible and out-of-spec readings.
                    valid_o <= rounded >= -40 && rounded <= 125;
                    state <= IDLE;
                end
            endcase
            // MIG exports no conversion-valid pulse. A UI-clock heartbeat
            // catches loss of the source clock; constant temperature is valid.
            if (!available_i || !alive || timeout_count == 0) valid_o <= 0;
        end
    end
endmodule
