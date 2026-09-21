`timescale 1ns/1ps
module tb_k2_temperature;
    logic clk = 0, reset = 1, heartbeat = 0, available = 1;
    always #5 clk = ~clk;
    logic [11:0] data = 0;
    wire valid;
    wire signed [9:0] degrees;
    k2_temperature #(.POLL_CYCLES(32), .TIMEOUT_CYCLES(64)) dut (
        .clk_i(clk), .reset_i(reset), .heartbeat_i(heartbeat), .raw_i(data),
        .available_i(available), .valid_o(valid), .degrees_o(degrees)
    );
    task automatic respond(input integer code);
        @(negedge clk); data=code; heartbeat=~heartbeat;
        wait(dut.state == 1);
        repeat (3) @(negedge clk);
    endtask
    integer code, expected, approximate;
    real physical;
    initial begin
        repeat (5) @(negedge clk); reset = 0;
        if (valid) $fatal(1, "valid before first reading");
        for (code = 0; code < 4096; code++) begin
            respond(code);
            physical = code * 503.975 / 4096.0 - 273.15;
            expected = $rtoi($floor(physical + 0.5));
            approximate = $rtoi($floor(code * 8064.0 / 65536.0 - 273.15 + 0.5));
            if (degrees !== approximate || degrees < expected || degrees > expected + 1)
                $fatal(1, "conversion code %0d got %0d expected %0d", code, degrees, approximate);
            if (valid !== (approximate >= -40 && approximate <= 125))
                $fatal(1, "range validation code %0d", code);
        end
        respond(2600);
        if (!valid) $fatal(1, "valid sample rejected");
        repeat (70) @(negedge clk);
        if (valid) $fatal(1, "timeout did not invalidate stale temperature");
        respond(2600);
        if (!valid) $fatal(1, "no recovery after timeout");
        available=0; @(negedge clk);
        if (valid) $fatal(1, "calibration loss not propagated");
        available=1; respond(2600);
        if (!valid) $fatal(1, "no recovery after recalibration");
        @(negedge clk); reset = 1;
        @(negedge clk);
        if (valid) $fatal(1, "reset failed");
        $display("PASS: all 4096 ADC codes, rounding, range, timeout, recovery and reset");
        $finish;
    end
    initial begin #5_000_000; $fatal(1, "watchdog"); end
endmodule

module tb_k2_xadc;
    logic clk = 0, reset = 1, mem_clk=0, xadc_clk=0, running=1;
    always #5 clk = ~clk;
    always #3 if (running) mem_clk=~mem_clk;
    always #2.5 xadc_clk=~xadc_clk;
    wire valid;
    wire [11:0] mem_raw, raw;
    wire available, heartbeat;
    wire signed [9:0] degrees;
    // Real generated MIG temperature monitor, real XADC model, and production
    // UI->100 MHz CDC. No second XADC and no changes to the vendor source.
    mig_7series_v4_2_tempmon tempmon (
        .clk(mem_clk), .xadc_clk(xadc_clk), .rst(reset),
        .device_temp_i(12'b0), .device_temp(mem_raw)
    );
    k2_temperature_source source (
        .mem_clk_i(mem_clk), .mem_reset_i(reset), .calibrated_i(!reset),
        .device_temp_i(mem_raw), .clk_i(clk), .raw_o(raw),
        .available_o(available), .heartbeat_o(heartbeat)
    );
    k2_temperature #(.POLL_CYCLES(100_000)) dut (
        .clk_i(clk), .reset_i(reset), .valid_o(valid), .degrees_o(degrees),
        .raw_i(raw), .available_i(available), .heartbeat_i(heartbeat)
    );
    initial begin
        #1000; reset = 0;
        #3_000_000;
        if (!valid || degrees < 20 || degrees > 30)
            $fatal(1, "XADC default 25 C model: valid=%b temperature=%0d", valid, degrees);
        force mem_raw=12'h7ff; #200; if(raw!==12'h7ff) $fatal(1,"CDC 7ff");
        force mem_raw=12'h800; #200; if(raw!==12'h800) $fatal(1,"CDC 800");
        release mem_raw;
        @(negedge mem_clk); running=0;
        #11_000_000;
        if(valid) $fatal(1,"stopped UI clock not detected");
        running=1; #2_000_000;
        if(!valid || degrees!=25) $fatal(1,"UI clock recovery");
        $display("PASS: real MIG/XADC 25 C, coherent CDC, stopped-clock watchdog and recovery");
        $finish;
    end
endmodule
