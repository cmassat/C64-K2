# Run against an open implemented K2 design. Keep direct-socket pin selection
# and the synchronizer attributes part of build sign-off, not just simulation.
proc k2_check_ps2 {} {
   foreach {name pin} {PS2_KB_CLK_io K22 PS2_KB_DATA_io K23} {
      set port [get_ports $name]
      if {[get_property PACKAGE_PIN $port] ne $pin ||
          [get_property IOSTANDARD $port] ne "LVCMOS33" ||
          [get_property DIRECTION $port] ne "INOUT"} {
         error "Wrong direct-socket PS/2 I/O configuration: $name"
      }
      puts "PS2_IO_CHECK: $name $pin LVCMOS33 INOUT"
   }
   foreach {stage port} {clk_meta PS2_KB_CLK_io dat_meta PS2_KB_DATA_io} {
      set input_pin [get_pins i_system/i_ps2_mouse/${stage}_reg/D]
      set sources [get_property NAME [all_fanin -flat -startpoints_only -to $input_pin]]
      if {[lsearch -exact $sources $port] < 0} {
         error "PS/2 receiver $stage is not connected to direct-socket port $port"
      }
      puts "PS2_CONNECTION_CHECK: $port reaches $stage"
   }
   foreach name {clk_meta clk_sync dat_meta dat_sync} {
      set cell [get_cells i_system/i_ps2_mouse/${name}_reg]
      if {[llength $cell] != 1 || ![get_property ASYNC_REG $cell]} {
         error "Missing PS/2 synchronizer property: $name"
      }
      puts "PS2_CDC_CHECK: $name ASYNC_REG=TRUE"
   }
}
