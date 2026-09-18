`timescale 1ns/1ps
module tb_k2_lcd_footer;
    logic clk = 0, reset = 1, update_req = 0;
    always #5 clk = ~clk;
    wire ready, bl, cs, dc, mosi, sclk, panel_reset, done;
    wire [7:0] x;
    wire [4:0] y;
    wire [15:0] pixel;
    logic signed [9:0] degrees = 47;
    logic valid = 1;
    k2_lcd_temperature text_pixels (
        .clk_i(clk), .x_i(x), .y_i(y), .degrees_i(degrees), .valid_i(valid), .pixel_o(pixel)
    );
    k2_lcd_rle #(.RESET_HOLD_CYCLES(2), .RESET_RELEASE_CYCLES(2),
        .SLEEP_OUT_CYCLES(2), .PANEL_WIDTH(1), .VISIBLE_HEIGHT(1)) dut (
        .clk_i(clk), .reset_i(reset), .run_address_o(), .run_word_i(16'h0000),
        .palette_address_o(), .palette_color_i(16'hffff),
        .update_i(update_req), .update_ready_o(ready), .footer_x_o(x), .footer_y_o(y),
        .footer_pixel_i(pixel), .lcd_bl_o(bl), .lcd_cs_n_o(cs), .lcd_dc_o(dc),
        .lcd_mosi_o(mosi), .lcd_sclk_o(sclk), .lcd_reset_n_o(panel_reset), .done_o(done)
    );
    // Independent golden frame generated from legible row strings in Python.
    logic [15:0] golden [0:10*7680-1];
    logic [7:0] command [0:10];
    logic checking = 0;
    integer frame = 0, count = 0, bit_count = 0, pixel_index;
    logic [7:0] received = 0, expected;
    logic expected_dc;
    time last_fall = 0, last_rise = 0;
    always @(posedge sclk) if (checking) begin
        if (cs || !panel_reset || !bl || !done) $fatal(1, "footer disturbed LCD state");
        if ($time - last_fall < 10) $fatal(1, "short SPI low phase");
        last_rise = $time;
        received = {received[6:0], mosi};
        if (bit_count == 7) begin
            if (count >= 11+15360) $fatal(1, "extra footer byte");
            if (count < 11) begin
                expected = command[count]; expected_dc = count != 0 && count != 5 && count != 10;
            end else begin
                pixel_index = frame*7680 + (count-11)/2;
                expected = (count-11)%2 == 0 ? golden[pixel_index][15:8] : golden[pixel_index][7:0];
                expected_dc = 1;
            end
            if (received !== expected || dc !== expected_dc)
                $fatal(1, "frame %0d byte %0d got %b/%02x expected %b/%02x",
                    frame, count, dc, received, expected_dc, expected);
            count++; bit_count = 0;
        end else bit_count++;
    end
    always @(negedge sclk) if (checking) begin
        if ($time-last_rise != 10) $fatal(1, "short SPI high phase");
        last_fall = $time;
    end
    task automatic send_frame;
        @(negedge clk); count = 0; bit_count = 0; checking = 1; update_req = 1;
        @(negedge clk); update_req = 0;
        wait (ready); @(negedge clk);
        if (count != 15371) $fatal(1, "incomplete footer: %0d", count);
        repeat (50) @(negedge clk);
        if (count != 15371) $fatal(1, "unexpected redraw");
        checking = 0;
    endtask
    initial begin
        $readmemh("footer.mem", golden);
        command[0]=8'h2a; command[1]=0; command[2]=0; command[3]=0; command[4]=239;
        command[5]=8'h2b; command[6]=1; command[7]=0; command[8]=1; command[9]=31; command[10]=8'h2c;
        repeat (5) @(negedge clk); reset = 0; wait (ready);
        send_frame();
        frame=1; degrees=-5; send_frame();
        frame=2; degrees=125; send_frame();
        frame=3; valid=0; send_frame();
        frame=4; valid=1; degrees=7; send_frame();
        frame=5; degrees=0; send_frame();
        frame=6; degrees=38; send_frame();
        frame=7; degrees=69; send_frame();
        frame=8; degrees=-40; send_frame();
        frame=9; degrees=100; send_frame();
        // Abort a footer mid-byte, park pins and redraw logo before accepting updates.
        @(negedge clk); update_req=1;
        @(negedge clk); update_req=0;
        repeat (7) @(posedge sclk);
        @(negedge clk); reset=1;
        @(negedge clk);
        if (bl || panel_reset || !cs || sclk || done || ready) $fatal(1, "footer reset failed");
        repeat (4) @(negedge clk); reset=0; wait(ready); send_frame();
        $display("PASS: footer window, ten full pixel fixtures/all glyphs, signed limits, SPI, erase and reset");
        $finish;
    end
    initial begin #50_000_000; $fatal(1, "watchdog"); end
endmodule
