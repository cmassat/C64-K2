`timescale 1ns/1ps
module tb_k2_lcd_snapshot;
    logic clk=0, reset=1;
    always #5 clk=~clk;
    wire bl, cs, dc, mosi, sclk, panel_reset;
    k2_lcd_splash dut (.clk_i(clk), .reset_i(reset), .lcd_bl_o(bl),
        .temperature_raw_i(12'b0), .temperature_available_i(1'b0), .temperature_heartbeat_i(1'b0),
        .lcd_cs_n_o(cs), .lcd_dc_o(dc), .lcd_mosi_o(mosi),
        .lcd_sclk_o(sclk), .lcd_reset_n_o(panel_reset));
    initial begin
        force dut.degrees = 10'sd47;
        force dut.valid = 1'b1;
        repeat (20) @(negedge clk); reset=0;
        // Skip only the already-tested panel delays; real logo is transmitted.
        dut.i_controller.delay_counter=0;
        wait(panel_reset); @(negedge clk); dut.i_controller.delay_counter=0;
        wait(dut.i_controller.state == 4); // ST_SLEEP_DELAY
        @(negedge clk); dut.i_controller.delay_counter=0;
        wait(dut.i_controller.updating); @(negedge clk);
        if (!bl || dut.frame_degrees != 47 || !dut.frame_valid)
            $fatal(1, "first footer snapshot/backlight");
        // Sensor changes in the middle of the transfer, not between frames.
        repeat (1000) @(negedge clk);
        force dut.degrees = 10'sd100;
        force dut.valid = 1'b0;
        while (!dut.update_ready) begin
            @(negedge clk);
            if (dut.frame_degrees != 47 || !dut.frame_valid)
                $fatal(1, "temperature tore mid-frame");
        end
        repeat (100) @(negedge clk);
        if (dut.refresh_count < 99_000_000 || dut.refresh_count >= 100_000_000)
            $fatal(1, "refresh timer not counting from one second");
        // Advance the timer to its last clock, without changing production RTL.
        dut.refresh_count=1;
        repeat (3) @(negedge clk);
        if (!dut.i_controller.updating || dut.frame_degrees != 100 || dut.frame_valid)
            $fatal(1, "next frame did not capture latest validity/value");
        reset=1; @(negedge clk);
        if (bl || panel_reset || !cs || sclk || dut.frame_valid)
            $fatal(1, "board reset did not clear snapshot/LCD");
        $display("PASS: complete splash integration, atomic snapshots, one-second timer and reset");
        $finish;
    end
    initial begin #50_000_000; $fatal(1, "watchdog"); end
endmodule
