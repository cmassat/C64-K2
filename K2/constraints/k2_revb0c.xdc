## C64MEGA65 for Wildbits K2 RevB0C
##
## K2-local board and timing constraints.  The M2M/ and CORE/ constraints
## target the MEGA65 physical shell, so their portable timing contracts are
## reproduced here with the K2 hierarchy.  DDR3 pin, PHY and UI constraints
## are emitted by the MIG generated from K2/ip/DDR3_CTRL/mig_a.prj.

################################################################################
## Board clocks
################################################################################

create_clock -period 25.000 -name board_clk40 \
   -waveform {0.000 12.500} [get_ports CLK_40_000Mhz_0_i]
create_clock -period 40.690 -name codec_mclk \
   -waveform {0.000 20.345} [get_ports CLK_24_576Mhz_0_i]

create_generated_clock -name clk \
   [get_pins i_clocks/i_mmcm/CLKOUT0]
create_generated_clock -name mem_sys_clk \
   [get_pins i_clocks/i_mmcm/CLKOUT1]
create_generated_clock -name mem_ref_clk \
   [get_pins i_clocks/i_mmcm/CLKOUT2]

create_generated_clock -name qnice_clk \
   [get_pins i_system/i_framework/i_clk_m2m/i_clk_qnice/CLKOUT0]
# The core-facing memory domain.  Same MMCM output the MEGA65 uses for its
# HyperRAM clock; on K2 it feeds the Avalon side of the DDR3 path, which
# crosses into MIG's ui_clk inside framework_k2's avm_fifo.
create_generated_clock -name hr_clk \
   [get_pins i_system/i_framework/i_clk_m2m/i_clk_qnice/CLKOUT1]
create_generated_clock -name audio_clk \
   [get_pins i_system/i_framework/i_clk_m2m/i_clk_audio/CLKOUT0]
create_generated_clock -name tmds_clk \
   [get_pins i_system/i_framework/i_video_out_clock/MMCM/CLKOUT0]
create_generated_clock -name hdmi_clk \
   [get_pins i_system/i_framework/i_video_out_clock/MMCM/CLKOUT1]

# video_out_clock.vhd uses a fabric divide-by-two input and a static mux.
create_generated_clock -name div_clk -source [get_pins i_clocks/i_mmcm/CLKOUT0] \
   -divide_by 2 [get_pins i_system/i_framework/i_video_out_clock/clki_div_reg/Q]
set_case_analysis 1 \
   [get_pins i_system/i_framework/i_video_out_clock/clk_mux_reg/Q]

# Core clock, ported from CORE/CORE.xdc with the K2 hierarchy (MEGA65 names the
# core instance "CORE"; here it is i_system/i_core).  These leaf names are
# intentionally load-bearing: a "no pins matched" warning silently no-ops STA,
# so grep every synthesis log for it.
#
# Assume the core runs at the original (slightly faster) PAL clock.  This halves
# the number of set_false_path needed.  NOTE the polarity is the opposite of
# AExp-K2's: C64MEGA65's fast leg is i_clk_c64_orig at core_speed 0, whereas
# AExp's native clock was below 50 Hz and its twin was the faster one.
set_case_analysis 0 [get_pins i_system/i_core/hr_core_speed_reg[0]/Q]
create_generated_clock -name main_clk \
   [get_pins i_system/i_core/clk_gen/i_clk_c64_orig/CLKOUT0]

# Simulated C1541 CDC, handled manually in the source code (CORE/CORE.xdc).
set_false_path -from [get_pins -hier id1_reg[*]/C]
set_false_path -from [get_pins -hier id2_reg[*]/C]
set_false_path -from [get_pins -hier busy_reg/C]
set_false_path -to   [get_pins i_system/i_core/i_main/iec_drive_inst/c1541/drives[*].c1541_drv/c1541_track/reset_sync/s1_reg[*]/D]
set_false_path -to   [get_pins i_system/i_core/i_main/iec_drive_inst/c1541/drives[*].c1541_drv/c1541_track/change_sync/s1_reg[*]/D]
set_false_path -to   [get_pins i_system/i_core/i_main/iec_drive_inst/c1541/drives[*].c1541_drv/c1541_track/save_sync/s1_reg[*]/D]
set_false_path -to   [get_pins i_system/i_core/i_main/iec_drive_inst/c1541/drives[*].c1541_drv/c1541_track/track_sync/s1_reg[*]/D]

# Disk type register: moves only on (re-)mount and is initialized from very
# stable signals (CORE/CORE.xdc).
set_false_path -from [get_pins i_system/i_core/i_main/iec_drive_inst/dtype_reg[*][*]/C]
set_false_path -to   [get_pins i_system/i_core/i_main/iec_drive_inst/dtype_reg[*][*]/D]

################################################################################
## Portable M2M and core timing contracts
################################################################################

set_false_path -from \
   [get_pins i_system/i_framework/i_reset_manager/reset_m2m_n_o_reg/C]
set_false_path -from \
   [get_pins i_system/i_framework/i_reset_manager/reset_core_n_o_reg/C]
set_false_path -from [get_ports COLD_RESETn_io]
set_false_path -from [get_ports C816_RSTn_io]

# K2 keyboard and PS/2 pins are asynchronous. Cut only the first stage of the
# explicit two-flop synchronizer; the second stage remains normally timed.
#
# The PS/2 mouse is not instantiated yet (milestone M4 adds the 1351 POT
# converter), so these two cuts would match nothing.  A "no pins matched"
# warning silently no-ops the constraint, so they stay commented out rather
# than dangling; re-enable them together with i_ps2_mouse.
# set_false_path -from [get_ports PS2_KB_CLK_io] -to \
#    [get_pins -hierarchical -regexp {.*/i_ps2_mouse/clk_meta_reg/D}]
# set_false_path -from [get_ports PS2_KB_DATA_io] -to \
#    [get_pins -hierarchical -regexp {.*/i_ps2_mouse/dat_meta_reg/D}]
set_false_path -from [get_ports {PB_io[*]}] -to \
   [get_pins -hierarchical -regexp {.*/pb_meta_reg\[[0-9]+\]/D}]
set_false_path -from [get_ports RESTOREn_KEY_i] -to \
   [get_pins -hierarchical -regexp {.*/restore_meta_n_reg/D}]
set_false_path -quiet -to \
   [get_pins -hierarchical -regexp {.*/i_m2m_keyb/key_state_meta_n_reg\[[0-9]+\]/D}]

# The optional recorder synchronizes the external debug UART into main_clk.
# Parallel RTC: externally timed, read-only data after a 1 us settling window.
# Only first-stage input FFs are asynchronous; second stages remain timed.
set_false_path -from [get_ports {C816_D_io[*]}] -to \
   [get_pins -hierarchical -regexp {i_rtc/data_meta_reg\[[0-9]+\]/D}]
# Bound FPGA control propagation; protocol allows 1 us per phase.
set_max_delay 10 -datapath_only -from [get_clocks clk] \
   -to [get_ports {C816_A_io[*] CS_RTCn_o BUS_OEn_o}]
set_false_path -quiet -from [get_ports DBG_RX_i] -to \
   [get_pins -quiet -hierarchical -regexp {.*i_trace/rx_meta_reg/D}]

# Independent LED status bits cross main_clk -> 100 MHz. Only the first
# stages are exempt; the second stages and serializer remain normally timed.
set_false_path -to \
   [get_pins -hierarchical -regexp {i_status_leds/status_meta_reg\[[0-9]+\]/D}]

# Stable-bundle CDCs are sampled only after the destination synchronizer.
set_max_delay 8 -datapath_only -from [get_generated_clocks] \
   -to [get_pins -hierarchical "*cdc_stable_gen.dst_*_d_reg[*]/D"]
set_max_delay 8 -datapath_only -from [get_clocks clk] \
   -to [get_pins -hierarchical "*cdc_stable_gen.dst_*_d_reg[*]/D"]

# QNICE SD clock divider and the EAE combinatorial divider.
create_generated_clock -name sdcard_clk \
   -source [get_pins i_system/i_framework/i_clk_m2m/i_clk_qnice/CLKOUT0] \
   -divide_by 2 \
   [get_pins i_system/i_framework/i_qnice_wrapper/QNICE_SOC/sd_card/Slow_Clock_25MHz_reg/Q]
set_multicycle_path \
   -from [get_cells -include_replicated {i_system/i_framework/i_qnice_wrapper/QNICE_SOC/eae_inst/op*_reg[*]}] \
   -to [get_cells -include_replicated {i_system/i_framework/i_qnice_wrapper/QNICE_SOC/eae_inst/res_reg[*]}] \
   -setup 3
set_multicycle_path \
   -from [get_cells -include_replicated {i_system/i_framework/i_qnice_wrapper/QNICE_SOC/eae_inst/op*_reg[*]}] \
   -to [get_cells -include_replicated {i_system/i_framework/i_qnice_wrapper/QNICE_SOC/eae_inst/res_reg[*]}] \
   -hold 2

# ascal uses explicit ping-pong buffers between three asynchronous domains.
# Its i/o/avl reset nets are asynchronous reset trees.  M2M/common.xdc cuts
# the source-level reset_na pin; match the synthesized nets here as well so
# the exception survives checkpoint link/flattening in the standalone target.
set_false_path -quiet -through \
   [get_nets -hierarchical -regexp {.*/i_ascal/(i_reset_na|o_reset_na|avl_reset_na)(|_.*)}]
set_false_path -quiet \
   -from [get_pins -hierarchical -regexp ".*/i_ascal/i_.*_reg.*/C"] \
   -to   [get_pins -hierarchical -regexp ".*/i_ascal/avl_.*_reg.*/D"]
set_false_path -quiet \
   -from [get_pins -hierarchical -regexp ".*/i_ascal/i_.*_reg.*/C"] \
   -to   [get_pins -hierarchical -regexp ".*/i_ascal/o_.*_reg.*/D"]
set_false_path -quiet \
   -from [get_pins -hierarchical -regexp ".*/i_ascal/avl_.*_reg.*/C"] \
   -to   [get_pins -hierarchical -regexp ".*/i_ascal/o_.*_reg.*/D"]
set_false_path -quiet \
   -from [get_pins -hierarchical -regexp ".*/i_ascal/o_.*_reg.*/C"] \
   -to   [get_pins -hierarchical -regexp ".*/i_ascal/i_.*_reg.*/D"]
set_false_path -quiet \
   -from [get_pins -hierarchical -regexp ".*/i_ascal/o_.*_reg.*/C"] \
   -to   [get_pins -hierarchical -regexp ".*/i_ascal/avl_.*_reg.*/D"]

set_false_path -from [get_clocks hdmi_clk]  -to [get_clocks audio_clk]
set_false_path -from [get_clocks audio_clk] -to [get_clocks hdmi_clk]
set_false_path -from [get_clocks qnice_clk] -to [get_clocks hdmi_clk]

# AExp-K2 bounds the ascal ping-pong CDCs here with two set_max_delay
# constraints on i_dpram_reg/avl_dr_reg and o_dpram_reg/o_dr_reg.  Those are
# NOT portable to this fork and are deliberately absent.
#
# They only bind when ascal's ping-pong buffers are LUTRAM, which is true only
# under AExp's "osm-scale" M2M patch (ram_style => "distributed" on i_dpram and
# o_dpram, plus RAM_STYLE_SELECT in tdp_ram.vhd).  This fork uses upstream M2M,
# where Vivado infers BRAM for those buffers, so no such cells exist and both
# constraints matched nothing -- silently no-opping, exactly the failure mode
# AGENTS.md rule 2 warns about.  Note these warnings appear in the IMPL log,
# not the synthesis log, because the first read defers them as black boxes.
#
# Upstream covers this CDC with the ascal set_false_path block above, which is
# what C64MEGA65 ships on the MEGA65 and what does bind here.  If the osm-scale
# patch is ever ported (it saves 4 RAMB36s), restore both constraints and bound
# the avl_ side by hr_clk's 10 ns period, not MIG's 6 ns.

################################################################################
## K2 RevB0C physical pins
################################################################################

set_property -dict {PACKAGE_PIN J26 IOSTANDARD LVCMOS33} [get_ports COLD_RESETn_io]
set_property -dict {PACKAGE_PIN E17 IOSTANDARD LVCMOS33} [get_ports CLK_40_000Mhz_0_i]
set_property -dict {PACKAGE_PIN G5  IOSTANDARD LVCMOS33} [get_ports CLK_24_576Mhz_0_i]

set_property -dict {PACKAGE_PIN AF5 IOSTANDARD LVCMOS33} [get_ports DBG_RX_i]
set_property -dict {PACKAGE_PIN AE5 IOSTANDARD LVCMOS33} [get_ports DBG_TX_o]
set_property -dict {PACKAGE_PIN AF4 IOSTANDARD LVCMOS33} [get_ports DBG_CTSn_o]

set_property -dict {PACKAGE_PIN AA23 IOSTANDARD LVCMOS33} [get_ports {PA_io[0]}]
set_property -dict {PACKAGE_PIN AB25 IOSTANDARD LVCMOS33} [get_ports {PA_io[1]}]
set_property -dict {PACKAGE_PIN AB26 IOSTANDARD LVCMOS33} [get_ports {PA_io[2]}]
set_property -dict {PACKAGE_PIN AA25 IOSTANDARD LVCMOS33} [get_ports {PA_io[3]}]
set_property -dict {PACKAGE_PIN AB24 IOSTANDARD LVCMOS33} [get_ports {PA_io[4]}]
set_property -dict {PACKAGE_PIN AC24 IOSTANDARD LVCMOS33} [get_ports {PA_io[5]}]
set_property -dict {PACKAGE_PIN AA24 IOSTANDARD LVCMOS33} [get_ports {PA_io[6]}]
set_property -dict {PACKAGE_PIN AC26 IOSTANDARD LVCMOS33} [get_ports {PA_io[7]}]
set_property -dict {PACKAGE_PIN AA22 IOSTANDARD LVCMOS33} [get_ports {PB_io[0]}]
set_property -dict {PACKAGE_PIN Y25  IOSTANDARD LVCMOS33} [get_ports {PB_io[1]}]
set_property -dict {PACKAGE_PIN Y26  IOSTANDARD LVCMOS33} [get_ports {PB_io[2]}]
set_property -dict {PACKAGE_PIN W25  IOSTANDARD LVCMOS33} [get_ports {PB_io[3]}]
set_property -dict {PACKAGE_PIN Y22  IOSTANDARD LVCMOS33} [get_ports {PB_io[4]}]
set_property -dict {PACKAGE_PIN Y21  IOSTANDARD LVCMOS33} [get_ports {PB_io[5]}]
set_property -dict {PACKAGE_PIN Y20  IOSTANDARD LVCMOS33} [get_ports {PB_io[6]}]
set_property -dict {PACKAGE_PIN Y23  IOSTANDARD LVCMOS33} [get_ports {PB_io[7]}]
set_property -dict {PACKAGE_PIN W26  IOSTANDARD LVCMOS33} [get_ports {PB_io[8]}]
set_property -dict {PACKAGE_PIN W23  IOSTANDARD LVCMOS33} [get_ports MECH_OPTICALn_i]

# Direct socket: pins 1/5 use the nominal KB pair, even for a mouse.
# Pins 2/6 (MS pair) are only reached through a splitter; keep them released.
# Reference: K2_Unified/constraints/common_current.xdc and K2 schematic J12.
# Board-side PS/2 circuitry supplies pull-ups; FPGA only pulls low or releases.
set_property -dict {PACKAGE_PIN K22 IOSTANDARD LVCMOS33} [get_ports PS2_KB_CLK_io]
set_property -dict {PACKAGE_PIN K23 IOSTANDARD LVCMOS33} [get_ports PS2_KB_DATA_io]
set_property -dict {PACKAGE_PIN J24 IOSTANDARD LVCMOS33} [get_ports PS2_MS_CLK_io]
set_property -dict {PACKAGE_PIN J23 IOSTANDARD LVCMOS33} [get_ports PS2_MS_DATA_io]

set_property -dict {PACKAGE_PIN AD3 IOSTANDARD LVCMOS33} [get_ports J1_UP_i]
set_property -dict {PACKAGE_PIN AD1 IOSTANDARD LVCMOS33} [get_ports J1_DOWN_i]
set_property -dict {PACKAGE_PIN AD5 IOSTANDARD LVCMOS33} [get_ports J1_LEFT_i]
set_property -dict {PACKAGE_PIN AD4 IOSTANDARD LVCMOS33} [get_ports J1_RIGHT_i]
set_property -dict {PACKAGE_PIN AC6 IOSTANDARD LVCMOS33} [get_ports J1_BTN0_i]
set_property -dict {PACKAGE_PIN AC1 IOSTANDARD LVCMOS33} [get_ports J0_UP_i]
set_property -dict {PACKAGE_PIN AC2 IOSTANDARD LVCMOS33} [get_ports J0_DOWN_i]
set_property -dict {PACKAGE_PIN AC4 IOSTANDARD LVCMOS33} [get_ports J0_LEFT_i]
set_property -dict {PACKAGE_PIN AC3 IOSTANDARD LVCMOS33} [get_ports J0_RIGHT_i]
set_property -dict {PACKAGE_PIN AB6 IOSTANDARD LVCMOS33} [get_ports J0_BTN0_i]

set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33} [get_ports F_SD0_CD_i]
set_property -dict {PACKAGE_PIN T15 IOSTANDARD LVCMOS33} [get_ports F_SD0_CLK_o]
set_property -dict {PACKAGE_PIN U17 IOSTANDARD LVCMOS33} [get_ports F_SD0_CMD_o]
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33} [get_ports F_SD0_DAT0_i]
set_property -dict {PACKAGE_PIN W18 IOSTANDARD LVCMOS33} [get_ports F_SD0_DAT3_o]
set_property -dict {PACKAGE_PIN V26 IOSTANDARD LVCMOS33} [get_ports F_SD1_CLK_o]
set_property -dict {PACKAGE_PIN U25 IOSTANDARD LVCMOS33} [get_ports F_SD1_CMD_o]
set_property -dict {PACKAGE_PIN V24 IOSTANDARD LVCMOS33} [get_ports F_SD1_DAT0_i]
set_property -dict {PACKAGE_PIN U26 IOSTANDARD LVCMOS33} [get_ports F_SD1_DAT3_o]

set_property -dict {PACKAGE_PIN B1 IOSTANDARD LVCMOS33} [get_ports CODEC_CE_o]
set_property -dict {PACKAGE_PIN A2 IOSTANDARD LVCMOS33} [get_ports CODEC_CL_o]
set_property -dict {PACKAGE_PIN B2 IOSTANDARD LVCMOS33} [get_ports CODEC_DI_o]
set_property -dict {PACKAGE_PIN C1 IOSTANDARD LVCMOS33} [get_ports CODEC_MCLK_o]
set_property -dict {PACKAGE_PIN F2 IOSTANDARD LVCMOS33} [get_ports CODEC_DAC_BCLK_o]
set_property -dict {PACKAGE_PIN E1 IOSTANDARD LVCMOS33} [get_ports CODEC_DAC_DAT_o]
set_property -dict {PACKAGE_PIN E2 IOSTANDARD LVCMOS33} [get_ports CODEC_DAC_LRCK_o]

set_property -dict {PACKAGE_PIN V14 IOSTANDARD LVCMOS33} [get_ports POWER_LED_o]
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS33} [get_ports SDCARD_LED_o]
set_property -dict {PACKAGE_PIN W24 IOSTANDARD LVCMOS33} [get_ports STATUS_RGB_3V3_o]
set_property -dict {PACKAGE_PIN U16 IOSTANDARD LVCMOS33} [get_ports STAT_LED0_o]
set_property -dict {PACKAGE_PIN T14 IOSTANDARD LVCMOS33} [get_ports STAT_LED1_o]

set_property -dict {PACKAGE_PIN D24 IOSTANDARD LVCMOS33} [get_ports iHDMI_CEC_io]
set_property -dict {PACKAGE_PIN A25 IOSTANDARD TMDS_33} [get_ports iHDMI_Ch0_n]
set_property -dict {PACKAGE_PIN B25 IOSTANDARD TMDS_33} [get_ports iHDMI_Ch0_p]
set_property -dict {PACKAGE_PIN B24 IOSTANDARD TMDS_33} [get_ports iHDMI_Ch1_n]
set_property -dict {PACKAGE_PIN C24 IOSTANDARD TMDS_33} [get_ports iHDMI_Ch1_p]
set_property -dict {PACKAGE_PIN A22 IOSTANDARD TMDS_33} [get_ports iHDMI_Ch2_n]
set_property -dict {PACKAGE_PIN B22 IOSTANDARD TMDS_33} [get_ports iHDMI_Ch2_p]
set_property -dict {PACKAGE_PIN A24 IOSTANDARD TMDS_33} [get_ports iHDMI_CLK_n]
set_property -dict {PACKAGE_PIN A23 IOSTANDARD TMDS_33} [get_ports iHDMI_CLK_p]
set_property -dict {PACKAGE_PIN C23 IOSTANDARD LVCMOS33} [get_ports iHDMI_HPD_i]
set_property -dict {PACKAGE_PIN B26 IOSTANDARD LVCMOS33} [get_ports iHDMI_SCL_io]
set_property -dict {PACKAGE_PIN C26 IOSTANDARD LVCMOS33} [get_ports iHDMI_SDA_io]
# Current B0C common_current.xdc identifies AA4 as the Restore key input;
# the older Project Common Source pinout called it an HDMI enable output.
set_property -dict {PACKAGE_PIN AA4 IOSTANDARD LVCMOS33} [get_ports RESTOREn_KEY_i]

# Parked 65C816 and 2 MiB asynchronous SRAM interface.
set_property -dict {PACKAGE_PIN V23 IOSTANDARD LVCMOS33} [get_ports C816_CLK_o]
set_property -dict {PACKAGE_PIN T20 IOSTANDARD LVCMOS33} [get_ports C816_RSTn_io]
set_property -dict {PACKAGE_PIN U20 IOSTANDARD LVCMOS33} [get_ports C816_RSTn_bis]
set_property -dict {PACKAGE_PIN L17 IOSTANDARD LVCMOS33} [get_ports BUS_OEn_o]
set_property -dict {PACKAGE_PIN AE20 IOSTANDARD LVCMOS33} [get_ports {MEM_A_o[0]}]
set_property -dict {PACKAGE_PIN AF22 IOSTANDARD LVCMOS33} [get_ports {MEM_A_o[1]}]
set_property -dict {PACKAGE_PIN AF23 IOSTANDARD LVCMOS33} [get_ports {MEM_A_o[2]}]
set_property -dict {PACKAGE_PIN AE21 IOSTANDARD LVCMOS33} [get_ports {MEM_A_o[3]}]
set_property -dict {PACKAGE_PIN AE22 IOSTANDARD LVCMOS33} [get_ports {MEM_A_o[4]}]
set_property -dict {PACKAGE_PIN Y18 IOSTANDARD LVCMOS33} [get_ports {MEM_A_o[5]}]
set_property -dict {PACKAGE_PIN AA18 IOSTANDARD LVCMOS33} [get_ports {MEM_A_o[6]}]
set_property -dict {PACKAGE_PIN AC18 IOSTANDARD LVCMOS33} [get_ports {MEM_A_o[7]}]
set_property -dict {PACKAGE_PIN AD18 IOSTANDARD LVCMOS33} [get_ports {MEM_A_o[8]}]
set_property -dict {PACKAGE_PIN Y17 IOSTANDARD LVCMOS33} [get_ports {MEM_A_o[9]}]
set_property -dict {PACKAGE_PIN AD20 IOSTANDARD LVCMOS33} [get_ports {MEM_A_o[10]}]
set_property -dict {PACKAGE_PIN AB20 IOSTANDARD LVCMOS33} [get_ports {MEM_A_o[11]}]
set_property -dict {PACKAGE_PIN AA20 IOSTANDARD LVCMOS33} [get_ports {MEM_A_o[12]}]
set_property -dict {PACKAGE_PIN AD21 IOSTANDARD LVCMOS33} [get_ports {MEM_A_o[13]}]
set_property -dict {PACKAGE_PIN AC21 IOSTANDARD LVCMOS33} [get_ports {MEM_A_o[14]}]
set_property -dict {PACKAGE_PIN AD26 IOSTANDARD LVCMOS33} [get_ports {MEM_A_o[15]}]
set_property -dict {PACKAGE_PIN AD25 IOSTANDARD LVCMOS33} [get_ports {MEM_A_o[16]}]
set_property -dict {PACKAGE_PIN AE26 IOSTANDARD LVCMOS33} [get_ports {MEM_A_o[17]}]
set_property -dict {PACKAGE_PIN AE25 IOSTANDARD LVCMOS33} [get_ports {MEM_A_o[18]}]
set_property -dict {PACKAGE_PIN AA19 IOSTANDARD LVCMOS33} [get_ports {MEM_A_o[19]}]
set_property -dict {PACKAGE_PIN AF25 IOSTANDARD LVCMOS33} [get_ports {MEM_A_o[20]}]
set_property -dict {PACKAGE_PIN AF24 IOSTANDARD LVCMOS33} [get_ports {MEM_D_io[0]}]
set_property -dict {PACKAGE_PIN AD19 IOSTANDARD LVCMOS33} [get_ports {MEM_D_io[1]}]
set_property -dict {PACKAGE_PIN AC19 IOSTANDARD LVCMOS33} [get_ports {MEM_D_io[2]}]
set_property -dict {PACKAGE_PIN AB19 IOSTANDARD LVCMOS33} [get_ports {MEM_D_io[3]}]
set_property -dict {PACKAGE_PIN AB21 IOSTANDARD LVCMOS33} [get_ports {MEM_D_io[4]}]
set_property -dict {PACKAGE_PIN AC22 IOSTANDARD LVCMOS33} [get_ports {MEM_D_io[5]}]
set_property -dict {PACKAGE_PIN AC23 IOSTANDARD LVCMOS33} [get_ports {MEM_D_io[6]}]
set_property -dict {PACKAGE_PIN AD23 IOSTANDARD LVCMOS33} [get_ports {MEM_D_io[7]}]
set_property -dict {PACKAGE_PIN AF19 IOSTANDARD LVCMOS33} [get_ports {MEM_D_io[8]}]
set_property -dict {PACKAGE_PIN AF18 IOSTANDARD LVCMOS33} [get_ports {MEM_D_io[9]}]
set_property -dict {PACKAGE_PIN AA17 IOSTANDARD LVCMOS33} [get_ports {MEM_D_io[10]}]
set_property -dict {PACKAGE_PIN AB17 IOSTANDARD LVCMOS33} [get_ports {MEM_D_io[11]}]
set_property -dict {PACKAGE_PIN AC17 IOSTANDARD LVCMOS33} [get_ports {MEM_D_io[12]}]
set_property -dict {PACKAGE_PIN AD17 IOSTANDARD LVCMOS33} [get_ports {MEM_D_io[13]}]
set_property -dict {PACKAGE_PIN AE17 IOSTANDARD LVCMOS33} [get_ports {MEM_D_io[14]}]
set_property -dict {PACKAGE_PIN AF17 IOSTANDARD LVCMOS33} [get_ports {MEM_D_io[15]}]
set_property -dict {PACKAGE_PIN AE23 IOSTANDARD LVCMOS33} [get_ports MEM_CSn_o]
set_property -dict {PACKAGE_PIN AD24 IOSTANDARD LVCMOS33} [get_ports MEM_OEn_o]
set_property -dict {PACKAGE_PIN Y16 IOSTANDARD LVCMOS33} [get_ports MEM_WEn_o]
set_property -dict {PACKAGE_PIN AE18 IOSTANDARD LVCMOS33} [get_ports MEM_LBn_o]
set_property -dict {PACKAGE_PIN AF20 IOSTANDARD LVCMOS33} [get_ports MEM_UBn_o]

set_property -dict {PACKAGE_PIN M15 IOSTANDARD LVCMOS33} [get_ports CS_EXP256K2n_o]
set_property -dict {PACKAGE_PIN L14 IOSTANDARD LVCMOS33} [get_ports CS_FLASHn_o]
set_property -dict {PACKAGE_PIN L15 IOSTANDARD LVCMOS33} [get_ports CS_RTCn_o]
# BQ4802LY U4: schematic sheet 2 CPU A[3:0]/D[7:0]/RW; FPGA sheet 1.
# Cross-checked against canonical RevB0C XDC. CPU BE is disabled before driving.
set_property -dict {PACKAGE_PIN U24 IOSTANDARD LVCMOS33} [get_ports C816_BE_o]
set_property -dict {PACKAGE_PIN T22 IOSTANDARD LVCMOS33} [get_ports {C816_A_io[0]}]
set_property -dict {PACKAGE_PIN T23 IOSTANDARD LVCMOS33} [get_ports {C816_A_io[1]}]
set_property -dict {PACKAGE_PIN R20 IOSTANDARD LVCMOS33} [get_ports {C816_A_io[2]}]
set_property -dict {PACKAGE_PIN R21 IOSTANDARD LVCMOS33} [get_ports {C816_A_io[3]}]
set_property -dict {PACKAGE_PIN N19 IOSTANDARD LVCMOS33} [get_ports {C816_D_io[0]}]
set_property -dict {PACKAGE_PIN N21 IOSTANDARD LVCMOS33} [get_ports {C816_D_io[1]}]
set_property -dict {PACKAGE_PIN N22 IOSTANDARD LVCMOS33} [get_ports {C816_D_io[2]}]
set_property -dict {PACKAGE_PIN M20 IOSTANDARD LVCMOS33} [get_ports {C816_D_io[3]}]
set_property -dict {PACKAGE_PIN M21 IOSTANDARD LVCMOS33} [get_ports {C816_D_io[4]}]
set_property -dict {PACKAGE_PIN M22 IOSTANDARD LVCMOS33} [get_ports {C816_D_io[5]}]
set_property -dict {PACKAGE_PIN M24 IOSTANDARD LVCMOS33} [get_ports {C816_D_io[6]}]
set_property -dict {PACKAGE_PIN M25 IOSTANDARD LVCMOS33} [get_ports {C816_D_io[7]}]
set_property -dict {PACKAGE_PIN T25 IOSTANDARD LVCMOS33} [get_ports C816_RWn_io]
set_property -dict {PACKAGE_PIN K26 IOSTANDARD LVCMOS33} [get_ports FLASH_WRn_o]
set_property -dict {PACKAGE_PIN M17 IOSTANDARD LVCMOS33} [get_ports RST_FLASHn_o]

# Parked peripheral controls.
set_property -dict {PACKAGE_PIN F3 IOSTANDARD LVCMOS33} [get_ports NET_CSn_o]
set_property -dict {PACKAGE_PIN C3 IOSTANDARD LVCMOS33} [get_ports NET_RDn_o]
set_property -dict {PACKAGE_PIN A3 IOSTANDARD LVCMOS33} [get_ports NET_WRn_o]
set_property -dict {PACKAGE_PIN A5 IOSTANDARD LVCMOS33} [get_ports NET_RSTn_o]
set_property -dict {PACKAGE_PIN U7 IOSTANDARD LVCMOS33} [get_ports WIFI_SPI_CS0n_o]
set_property -dict {PACKAGE_PIN V4 IOSTANDARD LVCMOS33} [get_ports SPLASH_SPI_CS1n_o]
set_property -dict {PACKAGE_PIN G7 IOSTANDARD LVCMOS33} [get_ports WIFI_RSTn_o]
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports PER_RSTn_o]
set_property -dict {PACKAGE_PIN J6 IOSTANDARD LVCMOS33} [get_ports SAM2695_RSTn_o]
set_property -dict {PACKAGE_PIN E6 IOSTANDARD LVCMOS33} [get_ports WAVETABLE_RST_o]
set_property -dict {PACKAGE_PIN K6 IOSTANDARD LVCMOS33} [get_ports SUPERVISOR_CSn_o]

# ST7789 LCD: RevB0C pins match the K2 reference and CX16 board shell.
# SPI mode 0, 50 MHz from clk_100; TE is unused for a one-shot static image.
set_property -dict {PACKAGE_PIN AB2 IOSTANDARD LVCMOS33} [get_ports LCD_CSn_o]
set_property -dict {PACKAGE_PIN AA5 IOSTANDARD LVCMOS33} [get_ports LCD_RSTn_o]
set_property -dict {PACKAGE_PIN AB5 IOSTANDARD LVCMOS33} [get_ports LCD_BL_o]
set_property -dict {PACKAGE_PIN AA8 IOSTANDARD LVCMOS33} [get_ports LCD_DC_o]
set_property -dict {PACKAGE_PIN AB1 IOSTANDARD LVCMOS33} [get_ports LCD_DIN_o]
set_property -dict {PACKAGE_PIN AB4 IOSTANDARD LVCMOS33} [get_ports LCD_SCLK_o]

################################################################################
## Configuration
################################################################################

set_property CONFIG_VOLTAGE                  3.3   [current_design]
set_property CFGBVS                          VCCO  [current_design]
# MUST stay FALSE, unlike AExp-K2.  The RP2040 FPGA manager checks the
# decompressed image against an exact FPGA_SIZE of 9730652 bytes
# (fpga_mgr.cpp) and rejects anything else, so a bitstream-compressed image
# (~5.2 MB) will not boot.  K2/scripts/make_core.py enforces the same size.
set_property BITSTREAM.GENERAL.COMPRESS      FALSE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE     66    [current_design]
set_property CONFIG_MODE                     SPIx4 [current_design]
# Vendor convention, matching Firmware/CNTX*/*.bin (foenix138.bin et al):
# 32 bytes of 0xFF dummy, bus-width detect at 32, sync word AA995566 at 48.
#
# History, because this flip-flopped once.  On 2026-09-19 a note here said this
# MUST stay YES, claiming the NO variant did not configure a RevB0C.  That test
# was made while the core painted a black screen from ANY image, so "did not
# configure" was indistinguishable from "configured and showed nothing".
#
# Re-tested 2026-09-21 once the core produced a picture: the NO variant boots
# from the RP2040 SD card and runs.  Diffing the two images, the ONLY difference
# in the configuration payload is one byte -- a Type-1 write to the BSPI
# register (0x3003E001), 0x0000026B vs 0x0000026C, the SPI flash read opcode
# (Quad Output Fast Read, 3- vs 4-byte address).  The FDRI payload is identical
# (sha256 78580b5198f2a3c2).  BSPI is only consulted in master SPI boot; this
# board configures in slave SelectMAP x8, so it is never read.
set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR NO    [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH   4     [current_design]
