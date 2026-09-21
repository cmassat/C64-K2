// C64 identification and live FPGA temperature on the K2's 240x280 LCD.
// Reset with the board, not with the emulated C64: the image stays visible
// across warm reset and QNICE menus. Neither external memory nor BRAM is used.
module k2_lcd_splash (
    input wire clk_i, reset_i,
    input wire [11:0] temperature_raw_i,
    input wire temperature_available_i, temperature_heartbeat_i,
    output wire lcd_bl_o, lcd_cs_n_o, lcd_dc_o, lcd_mosi_o,
    output wire lcd_sclk_o, lcd_reset_n_o
);
    wire [15:0] run_address, run_word, palette_color;
    wire [3:0] palette_address;
    wire signed [9:0] degrees;
    wire valid, update_ready;
    wire [7:0] footer_x;
    wire [4:0] footer_y;
    wire [15:0] footer_pixel;
    logic signed [9:0] frame_degrees;
    logic frame_valid;
    logic [26:0] refresh_count;
    wire update_request = update_ready && refresh_count == 0;

    k2_temperature i_temperature (
        .clk_i(clk_i), .reset_i(reset_i), .degrees_o(degrees), .valid_o(valid),
        .raw_i(temperature_raw_i), .available_i(temperature_available_i),
        .heartbeat_i(temperature_heartbeat_i)
    );
    // Snapshot once per footer so a sensor update cannot tear the digits.
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            refresh_count <= 0; frame_degrees <= 0; frame_valid <= 0;
        end else if (update_request) begin
            refresh_count <= 100_000_000-1;
            frame_degrees <= degrees; frame_valid <= valid;
        end else if (refresh_count != 0) refresh_count <= refresh_count - 1'b1;
    end
    k2_lcd_temperature i_text (
        .clk_i(clk_i), .x_i(footer_x), .y_i(footer_y), .degrees_i(frame_degrees),
        .valid_i(frame_valid), .pixel_o(footer_pixel)
    );

    c64_logo_rom i_logo (
        .run_address_i(run_address), .run_word_o(run_word),
        .palette_address_i(palette_address), .palette_color_o(palette_color)
    );
    k2_lcd_rle i_controller (
        .clk_i(clk_i), .reset_i(reset_i),
        .run_address_o(run_address), .run_word_i(run_word),
        .palette_address_o(palette_address), .palette_color_i(palette_color),
        .update_i(update_request), .update_ready_o(update_ready),
        .footer_x_o(footer_x), .footer_y_o(footer_y), .footer_pixel_i(footer_pixel),
        .lcd_bl_o(lcd_bl_o), .lcd_cs_n_o(lcd_cs_n_o), .lcd_dc_o(lcd_dc_o),
        .lcd_mosi_o(lcd_mosi_o), .lcd_sclk_o(lcd_sclk_o),
        .lcd_reset_n_o(lcd_reset_n_o), .done_o()
    );
endmodule
