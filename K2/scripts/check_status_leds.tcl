# Run with the implemented design open. Catch wrong board pins and lost CDCs.
proc k2_check_status_leds {} {
   set port [get_ports STATUS_RGB_3V3_o]
   if {[llength $port] != 1 ||
       [get_property PACKAGE_PIN $port] ne "W24" ||
       [get_property IOSTANDARD $port] ne "LVCMOS33" ||
       [get_property DIRECTION $port] ne "OUT"} {
      error "Wrong keyboard RGB LED I/O configuration"
   }
   foreach stage {meta sync} {
      set pattern [format {i_status_leds/status_%s_reg\[[0-2]\]} $stage]
      set cells [get_cells -hierarchical -regexp $pattern]
      if {[llength $cells] != 3} { error "Missing LED $stage synchronizer registers" }
      foreach cell $cells {
         if {![get_property ASYNC_REG $cell]} { error "Missing LED ASYNC_REG: $cell" }
      }
   }
   puts "LED_IO_CDC_CHECK: W24 LVCMOS33 OUT, six ASYNC_REG stages"
}
