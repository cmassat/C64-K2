# Run with the implemented design open. Logo/thermometer must not consume BRAM.
proc k2_check_lcd {} {
   foreach {name pin} {LCD_CSn_o AB2 LCD_RSTn_o AA5 LCD_BL_o AB5 LCD_DC_o AA8 LCD_DIN_o AB1 LCD_SCLK_o AB4} {
      set port [get_ports $name]
      if {[llength $port] != 1 || [get_property PACKAGE_PIN $port] ne $pin ||
          [get_property IOSTANDARD $port] ne "LVCMOS33" ||
          [get_property DIRECTION $port] ne "OUT"} {
         error "Wrong LCD I/O configuration: $name"
      }
   }
   set lcd_cells [get_cells -hierarchical -filter {NAME =~ i_lcd/*}]
   if {![llength $lcd_cells]} { error "LCD controller was not synthesized" }
   set brams [filter $lcd_cells {REF_NAME =~ RAMB*}]
   if {[llength $brams]} { error "LCD unexpectedly consumes BRAM: $brams" }
   if {[llength [filter $lcd_cells {REF_NAME =~ DSP*}]]} {
      error "LCD/temperature unexpectedly consumes DSPs"
   }
   set adc [get_cells -hierarchical -filter {REF_NAME == XADC}]
   if {[llength $adc] != 1 || ![string match {i_mig/*} [get_property NAME $adc]]} {
      error "MIG must own the only XADC; LCD must reuse its device_temp output"
   }
   foreach {prop expected} {INIT_40 1000 INIT_41 2fff INIT_42 0800 INIT_48 0101 INIT_49 0000 INIT_4A 0100} {
      set actual [get_property $prop $adc]
      if {![regexp -nocase {([0-9a-f]+)$} $actual -> digits] ||
          [scan $digits %x] != [scan $expected %x]} {
         error "Unexpected XADC $prop=$actual (expected hex $expected)"
      }
   }
   foreach pin {DWE DADDR[0] DADDR[1] DADDR[2] DADDR[3] DADDR[4] DADDR[5] DADDR[6]} {
      set input_pin [get_pins -of_objects $adc -filter "REF_PIN_NAME == $pin"]
      set drivers [get_cells -of_objects [get_pins -leaf -of_objects [get_nets -of_objects $input_pin] -filter {DIRECTION == OUT}]]
      if {[llength $drivers] != 1 || [get_property REF_NAME $drivers] ne "GND"} {
         error "XADC $pin must be fixed low (read-only temperature address)"
      }
   }
   set adc_clock [get_clocks -of_objects [get_pins -of_objects $adc -filter {REF_PIN_NAME == DCLK}]]
   if {[llength $adc_clock] != 1 || abs([get_property PERIOD $adc_clock] - 5.0) > 0.001} {
      error "MIG XADC must retain its fixed 200 MHz clock"
   }
   set cdc [get_cells -hierarchical -filter {NAME =~ i_temperature_source/i_cdc/* && ASYNC_REG == TRUE}]
   if {[llength $cdc] != 28} { error "Expected two ASYNC_REG stages for 14-bit temperature CDC" }
   puts "LCD_IO_ROM_CHECK: six RevB0C outputs; zero LCD BRAM/DSP; sole MIG XADC unchanged; temperature CDC"
}
