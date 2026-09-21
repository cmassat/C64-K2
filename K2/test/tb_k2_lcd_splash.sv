// SPDX-License-Identifier: CERN-OHL-P-2.0
// Initialization expectations adapted from x16-core tb_k2_lcd_splash.sv at
// 0976edf891773164132a749d679a4b671ee5fe6a. License: K2/licenses/CERN-OHL-P-2.0.txt.
// Modified 2026-09-11 by Matthias Brukner: RLE, full asset, SPI timing/reset tests.
`timescale 1ns/1ps
module tb_k2_lcd_splash #(
    parameter integer LONG_RUNS = 0,
    parameter integer REAL_LOGO = 0
);
    localparam integer WIDTH = (LONG_RUNS || REAL_LOGO) ? 240 : 4;
    localparam integer HEIGHT = REAL_LOGO ? 280 : (LONG_RUNS ? 20 : 3);
    localparam integer Y_START = REAL_LOGO ? 20 : 1;
    localparam integer PIXELS = WIDTH * HEIGHT;
    localparam integer BYTE_COUNT = 71 + PIXELS * 2;
    logic clk = 0, reset = 1;
    always #5 clk = ~clk;
    wire lcd_bl, lcd_cs_n, lcd_dc, lcd_mosi, lcd_sclk, lcd_reset_n, done;
    wire [15:0] address, run_word, palette_color;
    wire [3:0] palette_address;
    generate
        if (REAL_LOGO) begin
            c64_logo_rom rom (
                .run_address_i(address), .run_word_o(run_word),
                .palette_address_i(palette_address), .palette_color_o(palette_color)
            );
        end else begin
            // Small: black5/red1/green1/black5 (runs cross raster rows).
            // Long: black4096/red1/green702/black1 (maximum and singleton runs).
            assign run_word = address == 0 ? (LONG_RUNS ? 16'hfff0 : 16'h0040) :
                              address == 1 ? 16'h0001 :
                              address == 2 ? (LONG_RUNS ? 16'h2bd2 : 16'h0002) :
                              address == 3 ? (LONG_RUNS ? 16'h0000 : 16'h0040) : 16'hxxxx;
            assign palette_color = palette_address == 0 ? 16'h0000 :
                                   palette_address == 1 ? 16'hf800 :
                                   palette_address == 2 ? 16'h07e0 : 16'hxxxx;
        end
    endgenerate
    k2_lcd_rle #(
        .RESET_HOLD_CYCLES(4), .RESET_RELEASE_CYCLES(5), .SLEEP_OUT_CYCLES(6),
        .PANEL_WIDTH(WIDTH), .VISIBLE_HEIGHT(HEIGHT), .VISIBLE_Y_START(Y_START)
    ) dut (
        .clk_i(clk), .reset_i(reset), .run_address_o(address), .run_word_i(run_word),
        .palette_address_o(palette_address), .palette_color_i(palette_color),
        .update_i(1'b0), .update_ready_o(), .footer_x_o(), .footer_y_o(),
        .footer_pixel_i(16'hffff),
        .lcd_bl_o(lcd_bl), .lcd_cs_n_o(lcd_cs_n), .lcd_dc_o(lcd_dc),
        .lcd_mosi_o(lcd_mosi), .lcd_sclk_o(lcd_sclk),
        .lcd_reset_n_o(lcd_reset_n), .done_o(done)
    );
    logic [15:0] golden_pixels [0:PIXELS-1];
    logic [7:0] expected_data [0:BYTE_COUNT-1];
    logic expected_dc [0:BYTE_COUNT-1];
    integer expected_count = 0, observed_count = 0, bit_count = 0;
    logic [7:0] received = 0;
    time last_rise, last_fall = 0, reset_release, panel_release, sleep_sent;
    logic byte_dc;

    task automatic add_expected(input logic dc, input logic [7:0] data);
        expected_dc[expected_count] = dc;
        expected_data[expected_count] = data;
        expected_count++;
    endtask

    always @(posedge lcd_reset_n) if (!reset) begin
        if ($time - reset_release < 35) $fatal(1, "reset hold too short");
        panel_release = $time;
    end

    always @(posedge lcd_sclk) if (!reset) begin
        if (lcd_cs_n || !lcd_reset_n) $fatal(1, "SPI during deselect/panel reset");
        if (lcd_bl || done) $fatal(1, "SPI after backlight/done");
        if ($time - last_fall < 10) $fatal(1, "SPI low phase too short");
        last_rise = $time;
        if (bit_count == 0) byte_dc = lcd_dc;
        if (byte_dc !== lcd_dc) $fatal(1, "DC changed within byte");
        received = {received[6:0], lcd_mosi};
        if (bit_count == 7) begin
            if (observed_count >= expected_count) $fatal(1, "extra SPI byte");
            if (lcd_dc !== expected_dc[observed_count] ||
                received !== expected_data[observed_count])
                $fatal(1, "SPI byte %0d: got %b/%02x, expected %b/%02x",
                       observed_count, lcd_dc, received,
                       expected_dc[observed_count], expected_data[observed_count]);
            if (observed_count == 0) begin
                if ($time - panel_release < 50) $fatal(1, "panel recovery too short");
                sleep_sent = $time;
            end
            if (observed_count == 1 && $time - sleep_sent < 60)
                $fatal(1, "sleep-out recovery too short");
            observed_count++;
            bit_count = 0;
        end else bit_count++;
    end
    always @(negedge lcd_sclk) if (!reset) begin
        if ($time - last_rise != 10) $fatal(1, "SPI high phase not 10 ns");
        last_fall = $time;
    end

    task automatic restart;
        @(negedge clk); reset = 1;
        repeat (4) @(negedge clk);
        if (lcd_bl || lcd_reset_n || !lcd_cs_n || lcd_sclk || done)
            $fatal(1, "reset did not park LCD pins");
        observed_count = 0; bit_count = 0; received = 0;
        reset_release = $time;
        reset = 0;
    endtask

    task automatic await_frame;
        integer timeout;
        timeout = 0;
        while (!done && timeout < BYTE_COUNT * 25) begin
            @(negedge clk);
            timeout++;
            if (!done && lcd_bl) $fatal(1, "early backlight");
        end
        if (!done) $fatal(1, "timeout");
        if (!lcd_bl || !lcd_reset_n || !lcd_cs_n || lcd_sclk)
            $fatal(1, "incorrect idle state");
        if (observed_count != expected_count) $fatal(1, "incomplete raster");
        repeat (30) @(negedge clk);
        if (observed_count != expected_count) $fatal(1, "extra raster");
    endtask

    integer index;
    initial begin
        // Fixed initialization sequence through display inversion.
        add_expected(0, 8'h11);
        add_expected(0, 8'h36); add_expected(1, 8'h00);
        add_expected(0, 8'h3a); add_expected(1, 8'h05);
        add_expected(0, 8'hb2);
        add_expected(1, 8'h0c); add_expected(1, 8'h0c); add_expected(1, 8'h00);
        add_expected(1, 8'h33); add_expected(1, 8'h33);
        add_expected(0, 8'hb7); add_expected(1, 8'h35);
        add_expected(0, 8'hbb); add_expected(1, 8'h35);
        add_expected(0, 8'hc0); add_expected(1, 8'h2c);
        add_expected(0, 8'hc2); add_expected(1, 8'h01);
        add_expected(0, 8'hc3); add_expected(1, 8'h13);
        add_expected(0, 8'hc4); add_expected(1, 8'h20);
        add_expected(0, 8'hc6); add_expected(1, 8'h0f);
        add_expected(0, 8'hd0); add_expected(1, 8'ha4); add_expected(1, 8'ha1);
        add_expected(0, 8'he0);
        add_expected(1, 8'hf0); add_expected(1, 8'h00); add_expected(1, 8'h04);
        add_expected(1, 8'h04); add_expected(1, 8'h04); add_expected(1, 8'h05);
        add_expected(1, 8'h29); add_expected(1, 8'h33); add_expected(1, 8'h3e);
        add_expected(1, 8'h38); add_expected(1, 8'h12); add_expected(1, 8'h12);
        add_expected(1, 8'h28); add_expected(1, 8'h30);
        add_expected(0, 8'he1);
        add_expected(1, 8'hf0); add_expected(1, 8'h07); add_expected(1, 8'h0a);
        add_expected(1, 8'h0d); add_expected(1, 8'h0b); add_expected(1, 8'h07);
        add_expected(1, 8'h28); add_expected(1, 8'h33); add_expected(1, 8'h3e);
        add_expected(1, 8'h36); add_expected(1, 8'h14); add_expected(1, 8'h14);
        add_expected(1, 8'h29); add_expected(1, 8'h32);
        add_expected(0, 8'h21);


        add_expected(0, 8'h2a);
        add_expected(1, 0); add_expected(1, 0);
        add_expected(1, (WIDTH - 1) >> 8); add_expected(1, WIDTH - 1);
        add_expected(0, 8'h2b);
        add_expected(1, Y_START >> 8); add_expected(1, Y_START);
        add_expected(1, (Y_START + HEIGHT - 1) >> 8);
        add_expected(1, Y_START + HEIGHT - 1);
        add_expected(0, 8'h2c);
        if (REAL_LOGO) $readmemh("expected_pixels.mem", golden_pixels);
        else for (index = 0; index < PIXELS; index++) begin
            if (LONG_RUNS)
                golden_pixels[index] = index < 4096 ? 0 :
                                       index == 4096 ? 16'hf800 :
                                       index < 4799 ? 16'h07e0 : 0;
            else
                golden_pixels[index] = index == 5 ? 16'hf800 :
                                       index == 6 ? 16'h07e0 : 0;
        end
        for (index = 0; index < PIXELS; index++) begin
            add_expected(1, golden_pixels[index][15:8]);
            add_expected(1, golden_pixels[index][7:0]);
        end
        add_expected(0, 8'h29);
        if (expected_count != BYTE_COUNT) $fatal(1, "incorrect test vector length");
        restart();
        if (!REAL_LOGO && !LONG_RUNS) begin
            // Abort partway through a pixel byte, then start over cleanly.
            wait (observed_count == 73);
            repeat (3) @(posedge lcd_sclk);
            restart();
        end
        await_frame();
        if (!REAL_LOGO && !LONG_RUNS) begin
            // A completed display must also survive board reset/reinitialization.
            restart();
            await_frame();
        end
        $display("PASS: LCD %0dx%0d, %0d exact SPI bytes, RLE/palette/timing/reset/backlight", WIDTH, HEIGHT, BYTE_COUNT);
        $finish;
    end
endmodule
