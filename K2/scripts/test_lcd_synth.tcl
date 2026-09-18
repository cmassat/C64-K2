# Standalone synthesis guard. Run from a scratch directory to keep reports out
# of the checkout: vivado -mode batch -source /path/to/this/script.tcl
set repo_dir [file normalize [file join [file dirname [info script]] ../..]]
create_project -in_memory -part xc7a200tfbg676-2
source [file join $repo_dir K2 scripts lcd_sources.tcl]
k2_add_lcd_sources $repo_dir
synth_design -top k2_lcd_splash -part xc7a200tfbg676-2 -mode out_of_context
create_clock -name lcd_clk -period 10.000 [get_ports clk_i]
set brams [get_cells -quiet -hierarchical -filter {REF_NAME =~ RAMB*}]
if {[llength $brams]} { error "LCD/temperature consumes BRAM: $brams" }
if {[llength [get_cells -quiet -hierarchical -filter {REF_NAME =~ DSP*}]]} {
   error "LCD/temperature consumes DSPs"
}
report_utilization -file lcd_utilization.rpt
report_timing_summary -file lcd_timing_synth.rpt
if {[get_property SLACK [get_timing_paths -delay_type max -max_paths 1]] < 0} {
   error "LCD/temperature fails standalone setup timing"
}
puts "PASS: standalone LCD/temperature synthesis and setup timing, zero BRAM/DSP"
close_project
