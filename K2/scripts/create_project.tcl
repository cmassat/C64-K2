# Create the standalone C64MEGA65 project for Wildbits K2 RevB0C.
#
# Usage:
#   vivado -mode batch -source K2/scripts/create_project.tcl
#
# The script reads the existing R3 project XML only to obtain the core's and
# M2M's canonical source order.  It never opens or modifies that project.
# K2-specific HDL, constraints and the DDR3 MIG are owned entirely by K2/.

set script_dir [file dirname [file normalize [info script]]]
set repo_dir   [file normalize [file join $script_dir ../..]]
set build_dir  [file normalize [file join $repo_dir K2 build]]
set project_dir [file join $build_dir project]
set ref_xpr    [file join $repo_dir CORE CORE-R3.xpr]
source [file join $script_dir config_variant.tcl]
set k2_config [k2_config_variant $repo_dir]

file mkdir $project_dir

# Several build inputs intentionally use paths relative to a normal
# CORE/*.runs/synth_1 working directory.  Reproduce that layout entirely
# inside the ignored build directory.
foreach tree_name {CORE M2M} {
   set tree_link [file join $project_dir $tree_name]
   if {![file exists $tree_link]} {
      file link -symbolic $tree_link [file join $repo_dir $tree_name]
   }
}

# tdp_ram.vhd opens the simulated 1541/1581 ROMs through
# .INITFILE("../../C64_MiSTerMEGA65/rtl/iec_drive/*.mif.hex"), resolved from the
# synthesis run directory.  For the MEGA65 projects that lands in CORE/; for K2
# it lands in K2/build/project/.  This link preserves the proven source-relative
# contract without modifying the C64 submodule.  (The OSM font resolves by a
# different route -- FONT_FILE's "../font/..." is relative to M2M/vhdl/, the
# directory of the tdp_ram.vhd that opens it -- so it needs no link.)
set core_link [file join $project_dir C64_MiSTerMEGA65]
if {![file exists $core_link]} {
   file link -symbolic $core_link \
      [file join $repo_dir CORE C64_MiSTerMEGA65]
}

set ref_fd [open $ref_xpr r]
set ref_xml [read $ref_fd]
close $ref_fd

set source_records {}
foreach {whole_match relative_name} \
        [regexp -all -inline {<File Path="\$PPRDIR/([^"]+)"} $ref_xml] {
   set source_name [file normalize [file join $repo_dir CORE $relative_name]]
   if {$source_name eq [file join $repo_dir CORE vhdl config.vhd]} {
      set source_name $k2_config
   }
   if {[file exists $source_name] &&
       [file extension $source_name] ni {.xdc .xci .tcl}} {
      lappend source_records $source_name
   }
}

create_project -force C64-K2-B0C $project_dir -part xc7a200tfbg676-2
set_property target_language VHDL [current_project]
set_property default_lib work [current_project]

add_files -norecurse $source_records

# Only use the SFType values known to be safe in the MEGA65 projects.
# Plain .v sources stay extension-inferred; these four .v files are SV,
# matching the SVerilog entries in CORE/CORE-R3.xpr.
set_property FILE_TYPE {VHDL 2008} [get_files -filter {NAME =~ *.vhd || NAME =~ *.vhdl}]
foreach sv_name {scandoubler.v audio_out.v iir_filter.v reu.v} {
   set sv_file [get_files -quiet -filter "NAME =~ */$sv_name"]
   if {[llength $sv_file]} {
      set_property FILE_TYPE SystemVerilog $sv_file
   }
}

set k2_vhdl [list \
   [file join $repo_dir M2M vhdl axi_fifo_small.vhd] \
   [file join $repo_dir K2 vhdl k2_m2m_keyb.vhd] \
   [file join $repo_dir K2 vhdl k2_ps2_mouse.vhd] \
   [file join $repo_dir K2 vhdl k2_status_leds.vhd] \
   [file join $repo_dir K2 vhdl k2_load_monitor.vhd] \
   [file join $repo_dir K2 vhdl k2_rtc.vhd] \
   [file join $repo_dir K2 vhdl k2_avm_increase.vhd] \
   [file join $repo_dir K2 vhdl k2_avm_read_guard.vhd] \
   [file join $repo_dir K2 vhdl avm_mig_bridge.vhd] \
   [file join $repo_dir K2 vhdl framework_k2.vhd] \
   [file join $repo_dir K2 vhdl k2_c64_system.vhd] \
   [file join $repo_dir K2 vhdl k2_clock_gen.vhd] \
   [file join $repo_dir K2 vhdl k2_keyboard_matrix.vhd] \
   [file join $repo_dir K2 vhdl k2_codec_audio.vhd] \
   [file join $repo_dir K2 vhdl k2_revb0c_top.vhd]]
add_files -norecurse $k2_vhdl
set_property FILE_TYPE {VHDL 2008} [get_files $k2_vhdl]
source [file join $script_dir lcd_sources.tcl]
k2_add_lcd_sources $repo_dir

set k2_xdc [file join $repo_dir K2 constraints k2_revb0c.xdc]
if {[file exists $k2_xdc]} {
   add_files -fileset constrs_1 -norecurse $k2_xdc
}

set ip_dir [file join $project_dir ip]
file mkdir $ip_dir
create_ip -name mig_7series -vendor xilinx.com -library ip -version 4.2 \
   -module_name DDR3_CTRL -dir $ip_dir
set_property CONFIG.XML_INPUT_FILE \
   [file join $repo_dir K2 ip DDR3_CTRL mig_a.prj] [get_ips DDR3_CTRL]
generate_target all [get_ips DDR3_CTRL]

set_property top k2_revb0c_top [get_filesets sources_1]
update_compile_order -fileset sources_1

set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]
add_files -fileset utils_1 -norecurse \
   [file join $repo_dir K2 scripts synth_pre.tcl]
set_property STEPS.SYNTH_DESIGN.TCL.PRE \
   [file join $repo_dir K2 scripts synth_pre.tcl] [get_runs synth_1]

puts "Created [file join $project_dir C64-K2-B0C.xpr]"
close_project
