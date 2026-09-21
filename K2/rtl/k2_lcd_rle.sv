// SPDX-License-Identifier: CERN-OHL-P-2.0
// Adapted from x16-core rtl/platform/k2_b0c/k2_lcd_splash.sv, commit
// 0976edf891773164132a749d679a4b671ee5fe6a; see ../licenses/CERN-OHL-P-2.0.txt.
// Modified 2026-09-11 by Matthias Brukner: replace framebuffer/BRAM reads
// with a palette/RLE stream. The K2 ST7789 initialization and SPI sequence
// retain the CX16 implementation. No dependency on Amiga memory or firmware.
`timescale 1ns/1ps

module k2_lcd_rle #(
    parameter integer RESET_HOLD_CYCLES = 2_000_000,
    parameter integer RESET_RELEASE_CYCLES = 12_000_000,
    parameter integer SLEEP_OUT_CYCLES = 12_000_000,
    parameter integer PANEL_WIDTH = 240,
    parameter integer VISIBLE_HEIGHT = 280,
    parameter integer VISIBLE_Y_START = 20
) (
    input  wire clk_i, reset_i,
    // Asynchronous LUT-ROM interface. Run = {12-bit count-minus-one, color}.
    // The stream must cover exactly PANEL_WIDTH * VISIBLE_HEIGHT pixels.
    output logic [15:0] run_address_o,
    input  wire [15:0] run_word_i,
    output logic [3:0] palette_address_o,
    input  wire [15:0] palette_color_i,
    // Accepted only when update_ready_o is high. Fixed 240x32 footer at
    // visible y=236, i.e. ST7789 RAM y=256..287. Logo area is not rewritten.
    input wire update_i,
    output wire update_ready_o,
    output logic [7:0] footer_x_o,
    output logic [4:0] footer_y_o,
    input wire [15:0] footer_pixel_i,
    output logic lcd_bl_o, lcd_cs_n_o, lcd_dc_o, lcd_mosi_o,
    output logic lcd_sclk_o, lcd_reset_n_o, done_o
);
    localparam integer VISIBLE_Y_END = VISIBLE_Y_START + VISIBLE_HEIGHT - 1;
    localparam integer INIT_COUNT = 70;
    localparam integer PIXEL_BITS = $clog2(PANEL_WIDTH * VISIBLE_HEIGHT + 1);
    localparam logic [15:0] PANEL_X_END_VALUE = PANEL_WIDTH - 1;
    localparam logic [15:0] WINDOW_Y_START_VALUE = VISIBLE_Y_START;
    localparam logic [15:0] WINDOW_Y_END_VALUE = VISIBLE_Y_END;

    // Entry bit 8 is the command/data level; bits 7:0 are the SPI byte. This
    // sequence follows the proven K2 boot-ROM setup, then selects only the
    // 240x280 portion visible through the enclosure.
    function automatic logic [8:0] init_entry(input logic [6:0] index);
        begin
            case (index)
                7'd0:  init_entry = {1'b0, 8'h11};
                7'd1:  init_entry = {1'b0, 8'h36};
                7'd2:  init_entry = {1'b1, 8'h00};
                7'd3:  init_entry = {1'b0, 8'h3a};
                7'd4:  init_entry = {1'b1, 8'h05};
                7'd5:  init_entry = {1'b0, 8'hb2};
                7'd6:  init_entry = {1'b1, 8'h0c};
                7'd7:  init_entry = {1'b1, 8'h0c};
                7'd8:  init_entry = {1'b1, 8'h00};
                7'd9:  init_entry = {1'b1, 8'h33};
                7'd10: init_entry = {1'b1, 8'h33};
                7'd11: init_entry = {1'b0, 8'hb7};
                7'd12: init_entry = {1'b1, 8'h35};
                7'd13: init_entry = {1'b0, 8'hbb};
                7'd14: init_entry = {1'b1, 8'h35};
                7'd15: init_entry = {1'b0, 8'hc0};
                7'd16: init_entry = {1'b1, 8'h2c};
                7'd17: init_entry = {1'b0, 8'hc2};
                7'd18: init_entry = {1'b1, 8'h01};
                7'd19: init_entry = {1'b0, 8'hc3};
                7'd20: init_entry = {1'b1, 8'h13};
                7'd21: init_entry = {1'b0, 8'hc4};
                7'd22: init_entry = {1'b1, 8'h20};
                7'd23: init_entry = {1'b0, 8'hc6};
                7'd24: init_entry = {1'b1, 8'h0f};
                7'd25: init_entry = {1'b0, 8'hd0};
                7'd26: init_entry = {1'b1, 8'ha4};
                7'd27: init_entry = {1'b1, 8'ha1};
                7'd28: init_entry = {1'b0, 8'he0};
                7'd29: init_entry = {1'b1, 8'hf0};
                7'd30: init_entry = {1'b1, 8'h00};
                7'd31: init_entry = {1'b1, 8'h04};
                7'd32: init_entry = {1'b1, 8'h04};
                7'd33: init_entry = {1'b1, 8'h04};
                7'd34: init_entry = {1'b1, 8'h05};
                7'd35: init_entry = {1'b1, 8'h29};
                7'd36: init_entry = {1'b1, 8'h33};
                7'd37: init_entry = {1'b1, 8'h3e};
                7'd38: init_entry = {1'b1, 8'h38};
                7'd39: init_entry = {1'b1, 8'h12};
                7'd40: init_entry = {1'b1, 8'h12};
                7'd41: init_entry = {1'b1, 8'h28};
                7'd42: init_entry = {1'b1, 8'h30};
                7'd43: init_entry = {1'b0, 8'he1};
                7'd44: init_entry = {1'b1, 8'hf0};
                7'd45: init_entry = {1'b1, 8'h07};
                7'd46: init_entry = {1'b1, 8'h0a};
                7'd47: init_entry = {1'b1, 8'h0d};
                7'd48: init_entry = {1'b1, 8'h0b};
                7'd49: init_entry = {1'b1, 8'h07};
                7'd50: init_entry = {1'b1, 8'h28};
                7'd51: init_entry = {1'b1, 8'h33};
                7'd52: init_entry = {1'b1, 8'h3e};
                7'd53: init_entry = {1'b1, 8'h36};
                7'd54: init_entry = {1'b1, 8'h14};
                7'd55: init_entry = {1'b1, 8'h14};
                7'd56: init_entry = {1'b1, 8'h29};
                7'd57: init_entry = {1'b1, 8'h32};
                7'd58: init_entry = {1'b0, 8'h21};
                7'd59: init_entry = {1'b0, 8'h2a};
                7'd60: init_entry = {1'b1, 8'h00};
                7'd61: init_entry = {1'b1, 8'h00};
                7'd62: init_entry = {1'b1, PANEL_X_END_VALUE[15:8]};
                7'd63: init_entry = {1'b1, PANEL_X_END_VALUE[7:0]};
                7'd64: init_entry = {1'b0, 8'h2b};
                7'd65: init_entry = {1'b1, WINDOW_Y_START_VALUE[15:8]};
                7'd66: init_entry = {1'b1, WINDOW_Y_START_VALUE[7:0]};
                7'd67: init_entry = {1'b1, WINDOW_Y_END_VALUE[15:8]};
                7'd68: init_entry = {1'b1, WINDOW_Y_END_VALUE[7:0]};
                7'd69: init_entry = {1'b0, 8'h2c};
                default: init_entry = 9'h000;
            endcase
        end
    endfunction

    // Constrain the small command table too: Vivado otherwise packs its
    // registered case-function lookup into a RAMB18 despite its tiny size.
    (* rom_style = "distributed" *) logic [8:0] init_rom [0:127];
    initial begin
        for (integer i = 0; i < 128; i++) init_rom[i] = init_entry(i);
    end

    logic       tx_start;
    logic [7:0] tx_data;
    logic       tx_dc;
    logic       tx_busy;
    logic       tx_done;
    logic [7:0] tx_shift;
    logic [2:0] tx_bit;
    logic       tx_rise;

    // Mode-0 transmitter. Each bit receives one 10 ns low and one 10 ns high
    // half-cycle on the 100 MHz K2 clock, for a 50 MHz LCD serial clock.
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            lcd_cs_n_o <= 1'b1;
            lcd_dc_o   <= 1'b0;
            lcd_mosi_o <= 1'b0;
            lcd_sclk_o <= 1'b0;
            tx_busy    <= 1'b0;
            tx_done    <= 1'b0;
            tx_shift   <= 8'h00;
            tx_bit     <= 3'd0;
            tx_rise    <= 1'b0;
        end else begin
            tx_done <= 1'b0;
            if (!tx_busy) begin
                lcd_cs_n_o <= 1'b1;
                lcd_sclk_o <= 1'b0;
                if (tx_start) begin
                    tx_shift   <= tx_data;
                    tx_bit     <= 3'd7;
                    tx_busy    <= 1'b1;
                    tx_rise    <= 1'b1;
                    lcd_cs_n_o <= 1'b0;
                    lcd_dc_o   <= tx_dc;
                    lcd_mosi_o <= tx_data[7];
                end
            end else if (tx_rise) begin
                lcd_sclk_o <= 1'b1;
                tx_rise    <= 1'b0;
            end else begin
                lcd_sclk_o <= 1'b0;
                if (tx_bit == 0) begin
                    lcd_cs_n_o <= 1'b1;
                    tx_busy    <= 1'b0;
                    tx_done    <= 1'b1;
                end else begin
                    tx_shift   <= {tx_shift[6:0], 1'b0};
                    tx_bit     <= tx_bit - 1'b1;
                    lcd_mosi_o <= tx_shift[6];
                    tx_rise    <= 1'b1;
                end
            end
        end
    end


    typedef enum logic [4:0] {
        ST_RESET_HOLD, ST_RESET_RELEASE, ST_INIT_REQUEST, ST_INIT_WAIT,
        ST_SLEEP_DELAY, ST_RUN_READ, ST_COLOR_READ,
        ST_PIXEL_HI_REQ, ST_PIXEL_HI_WAIT, ST_PIXEL_LO_REQ, ST_PIXEL_LO_WAIT,
        ST_DISPLAY_REQ, ST_DISPLAY_WAIT, ST_DONE,
        ST_WINDOW_REQ, ST_WINDOW_WAIT, ST_FOOTER_READ
    } state_t;
    state_t state;
    logic [31:0] delay_counter;
    logic [6:0] init_index;
    logic [15:0] pixel_word;
    logic [11:0] run_remaining;
    logic [PIXEL_BITS-1:0] pixels_remaining;
    logic updating;
    logic [3:0] window_index;
    logic [1:0] pixel_wait;
    assign update_ready_o = state == ST_DONE;
    function automatic [8:0] footer_command(input logic [3:0] index);
        case (index)
            0: footer_command = 9'h02a;
            1: footer_command = 9'h100;
            2: footer_command = 9'h100;
            3: footer_command = 9'h100;
            4: footer_command = 9'h1ef; // x=0..239
            5: footer_command = 9'h02b;
            6: footer_command = 9'h101;
            7: footer_command = 9'h100; // y start=256
            8: footer_command = 9'h101;
            9: footer_command = 9'h11f; // y end=287
            default: footer_command = 9'h02c;
        endcase
    endfunction
    wire [8:0] window_command = footer_command(window_index);
    wire [8:0] current_init_entry = init_rom[init_index];

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            lcd_bl_o <= 1'b0;
            lcd_reset_n_o <= 1'b0;
            done_o <= 1'b0;
            tx_start <= 1'b0;
            tx_data <= 8'h00;
            tx_dc <= 1'b0;
            state <= ST_RESET_HOLD;
            delay_counter <= RESET_HOLD_CYCLES - 1;
            init_index <= 0;
            pixel_word <= 0;
            run_address_o <= 0;
            palette_address_o <= 0;
            run_remaining <= 0;
            pixels_remaining <= PANEL_WIDTH * VISIBLE_HEIGHT - 1;
            updating <= 0; window_index <= 0;
            pixel_wait <= 0;
            footer_x_o <= 0; footer_y_o <= 0;
        end else begin
            tx_start <= 1'b0;
            case (state)
                ST_RESET_HOLD:
                    if (delay_counter == 0) begin
                        lcd_reset_n_o <= 1'b1;
                        delay_counter <= RESET_RELEASE_CYCLES - 1;
                        state <= ST_RESET_RELEASE;
                    end else delay_counter <= delay_counter - 1'b1;
                ST_RESET_RELEASE:
                    if (delay_counter == 0) state <= ST_INIT_REQUEST;
                    else delay_counter <= delay_counter - 1'b1;
                ST_INIT_REQUEST: begin
                    tx_dc <= current_init_entry[8];
                    tx_data <= current_init_entry[7:0];
                    tx_start <= 1'b1;
                    state <= ST_INIT_WAIT;
                end
                ST_INIT_WAIT:
                    if (tx_done) begin
                        if (init_index == 0) begin
                            init_index <= 1;
                            delay_counter <= SLEEP_OUT_CYCLES - 1;
                            state <= ST_SLEEP_DELAY;
                        end else if (init_index == INIT_COUNT - 1)
                            state <= ST_RUN_READ;
                        else begin
                            init_index <= init_index + 1'b1;
                            state <= ST_INIT_REQUEST;
                        end
                    end
                ST_SLEEP_DELAY:
                    if (delay_counter == 0) state <= ST_INIT_REQUEST;
                    else delay_counter <= delay_counter - 1'b1;
                // Separate run/palette cycles keep the two LUT lookups off
                // the same timing path. The selected color is held per run.
                ST_RUN_READ: begin
                    run_remaining <= run_word_i[15:4];
                    palette_address_o <= run_word_i[3:0];
                    state <= ST_COLOR_READ;
                end
                ST_COLOR_READ: begin
                    pixel_word <= palette_color_i;
                    state <= ST_PIXEL_HI_REQ;
                end
                ST_PIXEL_HI_REQ: begin
                    tx_dc <= 1'b1;
                    tx_data <= pixel_word[15:8];
                    tx_start <= 1'b1;
                    state <= ST_PIXEL_HI_WAIT;
                end
                ST_PIXEL_HI_WAIT:
                    if (tx_done) state <= ST_PIXEL_LO_REQ;
                ST_PIXEL_LO_REQ: begin
                    tx_dc <= 1'b1;
                    tx_data <= pixel_word[7:0];
                    tx_start <= 1'b1;
                    state <= ST_PIXEL_LO_WAIT;
                end
                ST_PIXEL_LO_WAIT:
                    if (tx_done) begin
                        if (updating) begin
                            pixel_wait <= 0;
                            if (footer_x_o == 239) begin
                                footer_x_o <= 0;
                                if (footer_y_o == 31) begin
                                    updating <= 0; state <= ST_DONE;
                                end else begin
                                    footer_y_o <= footer_y_o + 1'b1;
                                    state <= ST_FOOTER_READ;
                                end
                            end else begin
                                footer_x_o <= footer_x_o + 1'b1;
                                state <= ST_FOOTER_READ;
                            end
                        end else if (pixels_remaining == 0)
                            state <= ST_DISPLAY_REQ;
                        else begin
                            pixels_remaining <= pixels_remaining - 1'b1;
                            if (run_remaining == 0) begin
                                run_address_o <= run_address_o + 1'b1;
                                state <= ST_RUN_READ;
                            end else begin
                                run_remaining <= run_remaining - 1'b1;
                                state <= ST_PIXEL_HI_REQ;
                            end
                        end
                    end
                ST_DISPLAY_REQ: begin
                    tx_dc <= 1'b0;
                    tx_data <= 8'h29;
                    tx_start <= 1'b1;
                    state <= ST_DISPLAY_WAIT;
                end
                ST_DISPLAY_WAIT:
                    if (tx_done) begin
                        lcd_bl_o <= 1'b1;
                        done_o <= 1'b1;
                        state <= ST_DONE;
                    end
                ST_DONE: if (update_i) begin
                    updating <= 1; window_index <= 0;
                    pixel_wait <= 0;
                    footer_x_o <= 0; footer_y_o <= 0;
                    state <= ST_WINDOW_REQ;
                end
                ST_WINDOW_REQ: begin
                    tx_dc <= window_command[8]; tx_data <= window_command[7:0];
                    tx_start <= 1; state <= ST_WINDOW_WAIT;
                end
                ST_WINDOW_WAIT: if (tx_done) begin
                    if (window_index == 10) state <= ST_FOOTER_READ;
                    else begin
                        window_index <= window_index + 1'b1;
                        state <= ST_WINDOW_REQ;
                    end
                end
                ST_FOOTER_READ: begin
                    if (pixel_wait == 3) begin
                        pixel_word <= footer_pixel_i;
                        state <= ST_PIXEL_HI_REQ;
                    end else pixel_wait <= pixel_wait + 1'b1;
                end
                default: state <= ST_DONE;
            endcase
        end
    end
endmodule
