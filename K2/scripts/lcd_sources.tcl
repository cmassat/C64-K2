# Shared by project creation and upgrades; all assets are checkout-local.
proc k2_add_lcd_sources {repo_dir} {
   set source_file [file join $repo_dir K2/vhdl/k2_temperature_source.vhd]
   if {![llength [get_files -quiet $source_file]]} { add_files -norecurse $source_file }
   set_property FILE_TYPE {VHDL 2008} [get_files $source_file]
   foreach name {lib/font5x7/generated/wb_font5x7.v K2/rtl/k2_lcd_rle.sv K2/rtl/k2_lcd_splash.sv K2/rtl/k2_temperature.sv K2/rtl/k2_lcd_temperature.sv K2/assets/lcd/c64_logo_rom.sv} {
      set input_file [file join $repo_dir $name]
      if {![llength [get_files -quiet $input_file]]} { add_files -norecurse $input_file }
      set_property FILE_TYPE SystemVerilog [get_files $input_file]
   }
}
