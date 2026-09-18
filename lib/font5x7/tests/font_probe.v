// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Matthias Brukner
// Unrestricted character inputs; checks resource/timing cost of the FULL font.
module wb_font5x7_probe (
    input wire clk_i,
    input wire [7:0] char_i,
    output reg [34:0] glyph_o
);
    reg [7:0] character;
    wire [34:0] glyph;
    wb_font5x7 i_font (.char_i(character), .glyph_o(glyph));
    always @(posedge clk_i) begin
        character <= char_i;
        glyph_o <= glyph;
    end
endmodule
