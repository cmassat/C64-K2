// 240x32 white footer, with centered 3x scaled 5x7 glyphs: "FPGA  47°C".
// Three-stage LUT-based renderer; no framebuffer or BRAM. The controller
// allows four clocks after changing coordinates before consuming the pixel.
module k2_lcd_temperature (
    input wire clk_i,
    input wire [7:0] x_i,
    input wire [4:0] y_i,
    input wire signed [9:0] degrees_i,
    input wire valid_i,
    output logic [15:0] pixel_o
);
    // Shared printable-ASCII font; lookup stays combinational so the original
    // three-stage renderer and exact temperature-footer pixels are preserved.
    wire [34:0] glyph_bits;
    logic [7:0] ch;
    wb_font5x7 i_font (.char_i(ch), .glyph_o(glyph_bits));
    wire [7:0] offset_x = x_i - 8'd30;
    wire [4:0] offset_y = y_i - 5'd5;
    wire [7:0] magnitude = degrees_i < 0 ? -degrees_i : degrees_i;
    wire [7:0] below_hundred = magnitude >= 100 ? magnitude - 8'd100 : magnitude;
    logic [3:0] cell_x, tens, units;
    logic [2:0] column, row, column_d, row_d;
    logic inside_text, inside_d, negative, hundred, two_digits, valid;
    logic [34:0] bits;
    always_comb begin
        case (cell_x)
            0: ch = 8'h46; // F
            1: ch = 8'h50; // P
            2: ch = 8'h47; // G
            3: ch = 8'h41; // A
            5: ch = !valid ? 8'h2d : negative && two_digits ? 8'h2d : hundred ? 8'h31 : 8'h20;
            6: ch = !valid ? 8'h2d : two_digits ? 8'h30 + {4'b0,tens} : negative ? 8'h2d : 8'h20;
            7: ch = !valid ? 8'h2d : 8'h30 + {4'b0,units};
            8: ch = 8'hb0; // degree (single-byte codepoint, not UTF-8)
            9: ch = 8'h43; // C
            default: ch = 8'h20;
        endcase
    end
    always_ff @(posedge clk_i) begin
        // All division operands are explicitly narrow/unsigned. Never infer
        // a general signed 32-bit divider on the per-pixel path.
        cell_x <= offset_x / 8'd18;
        column <= (offset_x % 8'd18) / 8'd3;
        row <= offset_y / 5'd3;
        inside_text <= x_i >= 30 && x_i < 210 && y_i >= 5 && y_i < 26;
        tens <= below_hundred / 8'd10;
        units <= below_hundred % 8'd10;
        negative <= degrees_i < 0; hundred <= magnitude >= 100;
        two_digits <= magnitude >= 10; valid <= valid_i;

        bits <= glyph_bits;
        column_d <= column; row_d <= row; inside_d <= inside_text;

        pixel_o <= inside_d && column_d < 5 && bits[34-row_d*5-column_d] ? 16'h0000 : 16'hffff;
    end
endmodule
