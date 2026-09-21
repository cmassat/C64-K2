// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Matthias Brukner
`timescale 1ns/1ps
module tb_font;
    reg [7:0] character;
    wire [34:0] glyph;
    reg [34:0] expected [0:255];
    integer code;
    wb_font5x7 dut (.char_i(character), .glyph_o(glyph));
    initial begin
        $readmemh("font.mem", expected);
        for (code = 0; code < 256; code = code + 1) begin
            character = code;
            #1;
            if (glyph !== expected[code]) begin
                $display("FAIL: code %02x got %09x expected %09x", code, glyph, expected[code]);
                $finish;
            end
        end
        $display("PASS: all 256 codes, printable ASCII, degree and replacement glyph");
        $finish;
    end
endmodule
