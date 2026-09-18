# Build an already-created K2 project and emit compact sign-off reports.
# Usage:
#   vivado -mode batch -source K2/scripts/build.tcl -tclargs synth
#   vivado -mode batch -source K2/scripts/build.tcl -tclargs impl

set script_dir [file dirname [file normalize [info script]]]
set repo_dir   [file normalize [file join $script_dir ../..]]
set build_dir  [file join $repo_dir K2 build]
set project_dir [file join $build_dir project]
set build_mode [expr {[llength $argv] ? [lindex $argv 0] : "synth"}]
if {[llength $argv] > 1} {
   puts "ERROR: usage: build.tcl -tclargs synth|impl"
   exit 1
}

if {$build_mode ni {synth impl}} {
   puts "ERROR: build mode must be 'synth' or 'impl'"
   exit 1
}

# Vivado's batch mode exits 0 even when a sourced script raises, so a failing
# gate (or a check_*.tcl sign-off) would be reported to a CI caller as a pass.
# Run the whole build through a catch and translate any error into exit 1.
if {[catch {
   open_project [file join $project_dir C64-K2-B0C.xpr]
   source [file join $script_dir config_variant.tcl]
   k2_use_config_variant $repo_dir
   # Upgrade an existing project without regenerating its MIG IP.
   foreach relative_name {K2/vhdl/k2_ps2_mouse.vhd K2/vhdl/k2_status_leds.vhd K2/vhdl/k2_load_monitor.vhd K2/vhdl/k2_rtc.vhd} {
      set input_file [file join $repo_dir $relative_name]
      if {![llength [get_files -quiet $input_file]]} { add_files -norecurse $input_file }
      set_property FILE_TYPE {VHDL 2008} [get_files $input_file]
   }
   source [file join $script_dir lcd_sources.tcl]
   k2_add_lcd_sources $repo_dir
   update_compile_order -fileset sources_1
   reset_run synth_1
   launch_runs synth_1 -jobs 8
   wait_on_run synth_1
   set synth_status [get_property STATUS [get_runs synth_1]]
   if {![string match "synth_design Complete*" $synth_status]} {
      error "K2 synthesis failed: $synth_status"
   }

   open_run synth_1
   report_utilization -file [file join $build_dir utilization_synth.rpt]
   report_timing_summary -file [file join $build_dir timing_synth.rpt]

   if {$build_mode eq "impl"} {
      close_design
      reset_run impl_1
      launch_runs impl_1 -to_step write_bitstream -jobs 8
      wait_on_run impl_1
      set impl_status [get_property STATUS [get_runs impl_1]]
      if {![string match "write_bitstream Complete*" $impl_status]} {
         error "K2 implementation failed: $impl_status"
      }
      open_run impl_1
      # check_ps2.tcl is re-enabled in milestone M4, when i_ps2_mouse returns.
      source [file join $script_dir check_status_leds.tcl]
      k2_check_status_leds
      source [file join $script_dir check_lcd.tcl]
      k2_check_lcd
      source [file join $script_dir check_rtc.tcl]
      k2_check_rtc
      report_io -file [file join $build_dir io_placed.rpt]
      report_utilization -file [file join $build_dir utilization_placed.rpt]
      report_timing_summary -file [file join $build_dir timing_routed.rpt]
      report_route_status -file [file join $build_dir route_status.rpt]
      set bus_skew_report [file join $build_dir bus_skew_routed.rpt]
      report_bus_skew -warn_on_violation -file $bus_skew_report

      foreach {delay_type label} {max setup min hold} {
         set worst_path [get_timing_paths -delay_type $delay_type -max_paths 1]
         if {[llength $worst_path] == 0} {
            error "K2 implementation has no $label timing paths"
         }
         set worst_slack [get_property SLACK $worst_path]
         if {$worst_slack < 0.0} {
            error "K2 implementation fails $label timing: $worst_slack ns"
         }
      }

      set bus_skew_fd [open $bus_skew_report r]
      set bus_skew_text [read $bus_skew_fd]
      close $bus_skew_fd
      if {[string first "Slack (VIOLATED)" $bus_skew_text] >= 0} {
         error "K2 implementation fails a bus-skew constraint"
      }
   }

   close_project
} k2_err]} {
   puts "ERROR: $k2_err"
   exit 1
}
