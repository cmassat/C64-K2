# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Matthias Brukner
# Run from a scratch directory with Vivado; Artix-7 implementation smoke test.
set font_dir [file normalize [file join [file dirname [info script]] ..]]
create_project -in_memory -part xc7a200tfbg676-2
read_verilog [file join $font_dir generated wb_font5x7.v]
read_verilog [file join $font_dir tests font_probe.v]
synth_design -top wb_font5x7_probe -mode out_of_context -part xc7a200tfbg676-2
create_clock -period 10.000 -name font_clk [get_ports clk_i]
foreach kind {RAMB* DSP*} {
    if {[llength [get_cells -quiet -hierarchical -filter "REF_NAME =~ $kind"]]} {
        error "Font unexpectedly consumes $kind"
    }
}
report_utilization -file font_utilization.rpt
report_timing_summary -file font_timing.rpt
if {[get_property SLACK [get_timing_paths -delay_type max -max_paths 1]] < 0} {
    error "Font fails 100 MHz standalone setup timing"
}
puts "PASS: full 96-glyph font, 100 MHz setup timing, zero BRAM/DSP"
close_project
