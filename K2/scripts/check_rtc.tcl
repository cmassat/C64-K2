# Physical and CDC checks for the read-only BQ4802LY adapter.
proc k2_rtc_constant {port value} {
   set output_buffer [get_cells -of_objects [get_pins -leaf -of_objects \
      [get_nets -of_objects [get_ports $port]] -filter {DIRECTION == OUT || DIRECTION == INOUT}]]
   set input_net [get_nets -of_objects [get_pins $output_buffer/I]]
   set drivers [get_cells -of_objects [get_pins -leaf -of_objects $input_net -filter {DIRECTION == OUT}]]
   if {[llength $drivers] != 1 || [get_property REF_NAME $drivers] ne $value} {
      error "RTC safety: $port is not driven by $value"
   }
}
proc k2_check_rtc {} {
   foreach {name pin} {
      C816_BE_o U24 C816_RWn_io T25 CS_RTCn_o L15 BUS_OEn_o L17
      C816_A_io[0] T22 C816_A_io[1] T23 C816_A_io[2] R20 C816_A_io[3] R21
      C816_D_io[0] N19 C816_D_io[1] N21 C816_D_io[2] N22 C816_D_io[3] M20
      C816_D_io[4] M21 C816_D_io[5] M22 C816_D_io[6] M24 C816_D_io[7] M25
   } {
      set p [get_ports $name]
      if {[llength $p] != 1 || [get_property PACKAGE_PIN $p] ne $pin ||
          [get_property IOSTANDARD $p] ne "LVCMOS33"} {
         error "RTC pin mismatch: $name $pin"
      }
   }
   k2_rtc_constant C816_BE_o GND
   k2_rtc_constant C816_RWn_io VCC
   foreach port {MEM_CSn_o MEM_OEn_o MEM_WEn_o CS_FLASHn_o CS_EXP256K2n_o FLASH_WRn_o} {
      k2_rtc_constant $port VCC
   }
   foreach stage {data_meta data_sync} {
      for {set i 0} {$i < 8} {incr i} {
         set cell [get_cells [format {i_rtc/%s_reg[%d]} $stage $i]]
         if {[llength $cell] != 1 || ![get_property ASYNC_REG $cell]} {
            error "RTC missing ASYNC_REG: $stage $i"
         }
         if {$stage eq "data_meta"} {
            set starts [get_property NAME [all_fanin -flat -startpoints_only -to [get_pins $cell/D]]]
            if {[lsearch -exact $starts [format {C816_D_io[%d]} $i]] < 0} {
               error "RTC data bit $i is not connected to CPU data pin"
            }
         }
      }
   }
   for {set i 0} {$i < 8} {incr i} {
      set data_port [get_ports [format {C816_D_io[%d]} $i]]
      set driven [get_pins -quiet -leaf -of_objects [get_nets -of_objects $data_port] \
         -filter {DIRECTION == OUT || DIRECTION == INOUT}]
      if {[llength $driven]} { error "RTC data pin has an FPGA output driver: $driven" }
   }
   set cells [get_cells -hierarchical -filter {NAME =~ i_rtc/*}]
   if {![llength $cells] || [llength [filter $cells {REF_NAME =~ RAMB*}]]} {
      error "RTC missing or unexpectedly consumes BRAM"
   }
   set cdc [get_cells -hierarchical -filter {NAME =~ i_system/i_rtc_cdc/* && ASYNC_REG == TRUE}]
   if {![llength $cdc]} { error "RTC main-clock CDC missing" }
   foreach p [get_ports {C816_A_io[*] CS_RTCn_o BUS_OEn_o}] {
      set path [get_timing_paths -from [get_clocks clk] -to $p -delay_type max -max_paths 1]
      if {[llength $path] != 1 || [get_property REQUIREMENT $path] != 10.0 ||
          [get_property SLACK $path] < 0.0} {
         error "RTC output lacks a passing 10 ns datapath bound: $p"
      }
      puts "RTC_OUTPUT_TIMING: $p slack [get_property SLACK $path] ns"
   }
   puts "RTC_CHECK: B0C pins, CPU disabled, read-only bus, SRAM parked, CDC, zero BRAM PASS"
}
