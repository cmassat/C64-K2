----------------------------------------------------------------------------------
-- C64MEGA65 system integration for the Wildbits K2 RevB0C.
--
-- Board-independent physical details (MIG, matrix keyboard, codec and safe pin
-- states) live in k2_revb0c_top.vhd.  This layer joins the unmodified C64MEGA65
-- core to framework_k2 and intentionally preserves the normal M2M interfaces.
--
-- Derived from AExp-K2's k2_c64_system.vhd.  Differences versus that file, all
-- because the C64 core is not the Amiga core:
--   * no interlace (video_fl) -- the C64 is progressive only
--   * no main_mouse_* quadrature path -- the C64 1351 is proportional and is
--     read through the SID POT lines instead (planned: drive main_pot*)
--   * no trace/diagnostic bus (the Amiga CPU/chipset trace does not apply)
--   * iec_* and cart_* are parked: the K2 has neither connector
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_modes_pkg.all;

entity k2_c64_system is
   port (
      clk_100_i               : in    std_logic;
      reset_n_i               : in    std_logic;
      rtc_100_i               : in    std_logic_vector(64 downto 0);

      uart_rxd_i              : in    std_logic;
      uart_txd_o              : out   std_logic;

      tmds_data_p_o           : out   std_logic_vector(2 downto 0);
      tmds_data_n_o           : out   std_logic_vector(2 downto 0);
      tmds_clk_p_o            : out   std_logic;
      tmds_clk_n_o            : out   std_logic;
      hdmi_scl_io             : inout std_logic;
      hdmi_sda_io             : inout std_logic;

      sd_reset_o              : out   std_logic;
      sd_clk_o                : out   std_logic;
      sd_mosi_o               : out   std_logic;
      sd_miso_i               : in    std_logic;
      sd_cd_i                 : in    std_logic;
      sd2_reset_o             : out   std_logic;
      sd2_clk_o               : out   std_logic;
      sd2_mosi_o              : out   std_logic;
      sd2_miso_i              : in    std_logic;
      sd2_cd_i                : in    std_logic;

      key_state_n_i           : in    std_logic_vector(79 downto 0);
      ps2_mouse_clk_io        : inout std_logic;
      ps2_mouse_data_io       : inout std_logic;

      joy_1_up_n_i            : in    std_logic;
      joy_1_down_n_i          : in    std_logic;
      joy_1_left_n_i          : in    std_logic;
      joy_1_right_n_i         : in    std_logic;
      joy_1_fire_n_i          : in    std_logic;
      joy_2_up_n_i            : in    std_logic;
      joy_2_down_n_i          : in    std_logic;
      joy_2_left_n_i          : in    std_logic;
      joy_2_right_n_i         : in    std_logic;
      joy_2_fire_n_i          : in    std_logic;

      power_led_o             : out   std_logic;
      drive_led_o             : out   std_logic;
      power_led_col_o         : out   std_logic_vector(23 downto 0);
      drive_led_col_o         : out   std_logic_vector(23 downto 0);
      audio_clk_o             : out   std_logic;
      audio_reset_o           : out   std_logic;
      audio_left_o            : out   signed(15 downto 0);
      audio_right_o           : out   signed(15 downto 0);

      mem_clk_i               : in    std_logic;
      mem_rst_i               : in    std_logic;
      mem_calib_done_i        : in    std_logic;
      mem_app_addr_o          : out   std_logic_vector(26 downto 0);
      mem_app_cmd_o           : out   std_logic_vector(2 downto 0);
      mem_app_en_o            : out   std_logic;
      mem_app_rdy_i           : in    std_logic;
      mem_app_wdf_data_o      : out   std_logic_vector(63 downto 0);
      mem_app_wdf_end_o       : out   std_logic;
      mem_app_wdf_mask_o      : out   std_logic_vector(7 downto 0);
      mem_app_wdf_wren_o      : out   std_logic;
      mem_app_wdf_rdy_i       : in    std_logic;
      mem_app_rd_data_i       : in    std_logic_vector(63 downto 0);
      mem_app_rd_data_valid_i : in    std_logic;
      mem_app_rd_data_end_i   : in    std_logic
   );
end entity k2_c64_system;

architecture synthesis of k2_c64_system is

   signal main_clk              : std_logic;
   signal main_rst              : std_logic;
   signal qnice_clk             : std_logic;
   signal qnice_rst             : std_logic;
   signal main_qnice_reset      : std_logic;
   signal main_qnice_pause      : std_logic;
   signal main_reset_m2m        : std_logic;
   signal main_reset_core       : std_logic;
   signal main_key_num          : integer range 0 to 79;
   signal main_key_pressed_n    : std_logic;
   signal main_power_led        : std_logic;
   signal main_power_led_col    : std_logic_vector(23 downto 0);
   signal main_drive_led        : std_logic;
   signal main_drive_led_col    : std_logic_vector(23 downto 0);
   signal main_osm_control_m    : std_logic_vector(255 downto 0);
   signal main_qnice_gp_reg     : std_logic_vector(255 downto 0);
   signal main_audio_l          : signed(15 downto 0);
   signal main_audio_r          : signed(15 downto 0);

   signal video_clk             : std_logic;
   signal video_rst             : std_logic;
   signal video_ce              : std_logic;
   signal video_ce_ovl          : std_logic;
   signal video_red             : std_logic_vector(7 downto 0);
   signal video_green           : std_logic_vector(7 downto 0);
   signal video_blue            : std_logic_vector(7 downto 0);
   signal video_vs              : std_logic;
   signal video_hs              : std_logic;
   signal video_hblank          : std_logic;
   signal video_vblank          : std_logic;
   -- OSM hotkey.  The K2 optical scanner already turns the physical RESTORE key
   -- into logical slot 67 (Help), so the classic Help-only binding reaches the
   -- menu without a core-driven selection.  Milestone M2 moves RESTORE to slot 75
   -- (the C64 NMI) and re-points the menu at an Fn combo by changing these three.
   constant C_OSM_KEY_A         : integer range 0 to 79 := 67;
   constant C_OSM_KEY_B         : integer range 0 to 79 := 67;
   constant C_OSM_COMBO         : std_logic := '0';

   signal main_joy1_up_n        : std_logic;
   signal main_joy1_down_n      : std_logic;
   signal main_joy1_left_n      : std_logic;
   signal main_joy1_right_n     : std_logic;
   signal main_joy1_fire_n      : std_logic;
   signal main_joy2_up_n        : std_logic;
   signal main_joy2_down_n      : std_logic;
   signal main_joy2_left_n      : std_logic;
   signal main_joy2_right_n     : std_logic;
   signal main_joy2_fire_n      : std_logic;
   signal main_pot1_x           : std_logic_vector(7 downto 0);
   signal main_pot1_y           : std_logic_vector(7 downto 0);
   signal main_pot2_x           : std_logic_vector(7 downto 0);
   signal main_pot2_y           : std_logic_vector(7 downto 0);
   signal main_rtc              : std_logic_vector(64 downto 0);

   signal hr_clk                : std_logic;
   signal hr_rst                : std_logic;
   signal hr_core_write         : std_logic;
   signal hr_core_read          : std_logic;
   signal hr_core_address       : std_logic_vector(31 downto 0);
   signal hr_core_writedata     : std_logic_vector(15 downto 0);
   signal hr_core_byteenable    : std_logic_vector(1 downto 0);
   signal hr_core_burstcount    : std_logic_vector(7 downto 0);
   signal hr_core_readdata      : std_logic_vector(15 downto 0);
   signal hr_core_readdatavalid : std_logic;
   signal hr_core_waitrequest   : std_logic;
   signal hr_low                : std_logic;
   signal hr_high               : std_logic;

   signal qnice_dvi             : std_logic;
   signal qnice_video_mode      : video_mode_type;
   signal qnice_scandoubler     : std_logic;
   signal qnice_csync           : std_logic;
   signal qnice_audio_mute      : std_logic;
   signal qnice_audio_filter    : std_logic;
   signal qnice_zoom_crop       : std_logic;
   signal qnice_ascal_mode      : std_logic_vector(1 downto 0);
   signal qnice_ascal_polyphase : std_logic;
   signal qnice_ascal_triplebuf : std_logic;
   signal qnice_retro15khz      : std_logic;
   signal qnice_osm_cfg_scaling : std_logic_vector(8 downto 0);
   signal qnice_flip_joyports   : std_logic;
   signal qnice_osm_control_m   : std_logic_vector(255 downto 0);
   signal qnice_gp_reg          : std_logic_vector(255 downto 0);
   signal qnice_ramrom_dev      : std_logic_vector(15 downto 0);
   signal qnice_ramrom_addr     : std_logic_vector(27 downto 0);
   signal qnice_ramrom_data_out : std_logic_vector(15 downto 0);
   signal qnice_ramrom_data_in  : std_logic_vector(15 downto 0);
   signal qnice_ramrom_ce       : std_logic;
   signal qnice_ramrom_we       : std_logic;
   signal qnice_ramrom_wait     : std_logic;

   signal dummy_sda             : std_logic := 'H';
   signal dummy_scl             : std_logic := 'H';

begin

   power_led_o <= main_power_led;
   i_rtc_cdc : entity work.cdc_stable
      generic map (G_DATA_SIZE => 65, G_REGISTER_SRC => true)
      port map (src_clk_i => clk_100_i, src_data_i => rtc_100_i,
                dst_clk_i => main_clk, dst_data_o => main_rtc);
   drive_led_o <= main_drive_led;
   power_led_col_o <= main_power_led_col;
   drive_led_col_o <= main_drive_led_col;

   i_framework : entity work.framework_k2
      generic map (
         G_BOARD         => "K2_REVB0C",
         G_MEM_CLK_SPEED => 166_666_667
      )
      port map (
         clk_i                   => clk_100_i,
         reset_n_i               => reset_n_i,
         uart_rxd_i              => uart_rxd_i,
         uart_txd_o              => uart_txd_o,
         vga_red_o               => open,
         vga_green_o             => open,
         vga_blue_o              => open,
         vga_hs_o                => open,
         vga_vs_o                => open,
         vdac_clk_o              => open,
         vdac_sync_n_o           => open,
         vdac_blank_n_o          => open,
         tmds_data_p_o           => tmds_data_p_o,
         tmds_data_n_o           => tmds_data_n_o,
         tmds_clk_p_o            => tmds_clk_p_o,
         tmds_clk_n_o            => tmds_clk_n_o,
         key_state_n_i           => key_state_n_i,
         sd_reset_o              => sd_reset_o,
         sd_clk_o                => sd_clk_o,
         sd_mosi_o               => sd_mosi_o,
         sd_miso_i               => sd_miso_i,
         sd_cd_i                 => sd_cd_i,
         sd2_reset_o             => sd2_reset_o,
         sd2_clk_o               => sd2_clk_o,
         sd2_mosi_o              => sd2_mosi_o,
         sd2_miso_i              => sd2_miso_i,
         sd2_cd_i                => sd2_cd_i,
         joy_1_up_n_i            => joy_1_up_n_i,
         joy_1_down_n_i          => joy_1_down_n_i,
         joy_1_left_n_i          => joy_1_left_n_i,
         joy_1_right_n_i         => joy_1_right_n_i,
         joy_1_fire_n_i          => joy_1_fire_n_i,
         joy_1_up_n_o            => open,
         joy_1_down_n_o          => open,
         joy_1_left_n_o          => open,
         joy_1_right_n_o         => open,
         joy_1_fire_n_o          => open,
         joy_2_up_n_i            => joy_2_up_n_i,
         joy_2_down_n_i          => joy_2_down_n_i,
         joy_2_left_n_i          => joy_2_left_n_i,
         joy_2_right_n_i         => joy_2_right_n_i,
         joy_2_fire_n_i          => joy_2_fire_n_i,
         joy_2_up_n_o            => open,
         joy_2_down_n_o          => open,
         joy_2_left_n_o          => open,
         joy_2_right_n_o         => open,
         joy_2_fire_n_o          => open,
         paddle_i                => (others => '1'),
         paddle_drain_o          => open,
         mem_clk_i               => mem_clk_i,
         mem_rst_i               => mem_rst_i,
         mem_calib_done_i        => mem_calib_done_i,
         mem_app_addr_o          => mem_app_addr_o,
         mem_app_cmd_o           => mem_app_cmd_o,
         mem_app_en_o            => mem_app_en_o,
         mem_app_rdy_i           => mem_app_rdy_i,
         mem_app_wdf_data_o      => mem_app_wdf_data_o,
         mem_app_wdf_end_o       => mem_app_wdf_end_o,
         mem_app_wdf_mask_o      => mem_app_wdf_mask_o,
         mem_app_wdf_wren_o      => mem_app_wdf_wren_o,
         mem_app_wdf_rdy_i       => mem_app_wdf_rdy_i,
         mem_app_rd_data_i       => mem_app_rd_data_i,
         mem_app_rd_data_valid_i => mem_app_rd_data_valid_i,
         mem_app_rd_data_end_i   => mem_app_rd_data_end_i,
         qnice_clk_o             => qnice_clk,
         qnice_rst_o             => qnice_rst,
         main_clk_i              => main_clk,
         main_rst_i              => main_rst,
         main_qnice_reset_o      => main_qnice_reset,
         main_qnice_pause_o      => main_qnice_pause,
         main_reset_m2m_o        => main_reset_m2m,
         main_reset_core_o       => main_reset_core,
         main_key_num_o          => main_key_num,
         main_key_pressed_n_o    => main_key_pressed_n,
         main_power_led_i        => main_power_led,
         main_power_led_col_i    => main_power_led_col,
         main_drive_led_i        => main_drive_led,
         main_drive_led_col_i    => main_drive_led_col,
         main_osm_control_m_o    => main_osm_control_m,
         main_qnice_gp_reg_o     => main_qnice_gp_reg,
         main_audio_l_i          => main_audio_l,
         main_audio_r_i          => main_audio_r,
         video_clk_i             => video_clk,
         video_rst_i             => video_rst,
         video_ce_i              => video_ce,
         video_ce_ovl_i          => video_ce_ovl,
         video_red_i             => video_red,
         video_green_i           => video_green,
         video_blue_i            => video_blue,
         video_vs_i              => video_vs,
         video_hs_i              => video_hs,
         video_hblank_i          => video_hblank,
         video_vblank_i          => video_vblank,
         osm_key_a_i             => C_OSM_KEY_A,
         osm_key_b_i             => C_OSM_KEY_B,
         osm_combo_i             => C_OSM_COMBO,
         main_joy1_up_n_o        => main_joy1_up_n,
         main_joy1_down_n_o      => main_joy1_down_n,
         main_joy1_left_n_o      => main_joy1_left_n,
         main_joy1_right_n_o     => main_joy1_right_n,
         main_joy1_fire_n_o      => main_joy1_fire_n,
         main_joy1_up_n_i        => '1',
         main_joy1_down_n_i      => '1',
         main_joy1_left_n_i      => '1',
         main_joy1_right_n_i     => '1',
         main_joy1_fire_n_i      => '1',
         main_joy2_up_n_o        => main_joy2_up_n,
         main_joy2_down_n_o      => main_joy2_down_n,
         main_joy2_left_n_o      => main_joy2_left_n,
         main_joy2_right_n_o     => main_joy2_right_n,
         main_joy2_fire_n_o      => main_joy2_fire_n,
         main_joy2_up_n_i        => '1',
         main_joy2_down_n_i      => '1',
         main_joy2_left_n_i      => '1',
         main_joy2_right_n_i     => '1',
         main_joy2_fire_n_i      => '1',
         main_pot1_x_o           => main_pot1_x,
         main_pot1_y_o           => main_pot1_y,
         main_pot2_x_o           => main_pot2_x,
         main_pot2_y_o           => main_pot2_y,
         main_rtc_o              => open, -- MEGA65 I2C RTC is not K2's parallel RTC.
         audio_clk_o             => audio_clk_o,
         audio_reset_o           => audio_reset_o,
         audio_left_o            => audio_left_o,
         audio_right_o           => audio_right_o,
         hr_clk_o                => hr_clk,
         hr_rst_o                => hr_rst,
         hr_core_write_i         => hr_core_write,
         hr_core_read_i          => hr_core_read,
         hr_core_address_i       => hr_core_address,
         hr_core_writedata_i     => hr_core_writedata,
         hr_core_byteenable_i    => hr_core_byteenable,
         hr_core_burstcount_i    => hr_core_burstcount,
         hr_core_readdata_o      => hr_core_readdata,
         hr_core_readdatavalid_o => hr_core_readdatavalid,
         hr_core_waitrequest_o   => hr_core_waitrequest,
         hr_high_o               => hr_high,
         hr_low_o                => hr_low,
         qnice_dvi_i             => qnice_dvi,
         qnice_video_mode_i      => qnice_video_mode,
         qnice_osm_cfg_scaling_i => qnice_osm_cfg_scaling,
         qnice_retro15kHz_i      => qnice_retro15khz,
         qnice_scandoubler_i     => qnice_scandoubler,
         qnice_csync_i           => qnice_csync,
         qnice_audio_mute_i      => qnice_audio_mute,
         qnice_audio_filter_i    => qnice_audio_filter,
         qnice_zoom_crop_i       => qnice_zoom_crop,
         qnice_ascal_mode_i      => qnice_ascal_mode,
         qnice_ascal_polyphase_i => qnice_ascal_polyphase,
         qnice_ascal_triplebuf_i => qnice_ascal_triplebuf,
         qnice_flip_joyports_i   => qnice_flip_joyports,
         qnice_osm_control_m_o   => qnice_osm_control_m,
         qnice_gp_reg_o          => qnice_gp_reg,
         qnice_ramrom_dev_o      => qnice_ramrom_dev,
         qnice_ramrom_addr_o     => qnice_ramrom_addr,
         qnice_ramrom_data_out_o => qnice_ramrom_data_out,
         qnice_ramrom_data_in_i  => qnice_ramrom_data_in,
         qnice_ramrom_ce_o       => qnice_ramrom_ce,
         qnice_ramrom_we_o       => qnice_ramrom_we,
         qnice_ramrom_wait_i     => qnice_ramrom_wait,
         hdmi_scl_io             => hdmi_scl_io,
         hdmi_sda_io             => hdmi_sda_io,
         vga_scl_io              => dummy_scl,
         vga_sda_io              => dummy_sda,
         audio_scl_io            => dummy_scl,
         audio_sda_io            => dummy_sda,
         i2c_scl_io              => dummy_scl,
         i2c_sda_io              => dummy_sda,
         grove_scl_io            => dummy_scl,
         grove_sda_io            => dummy_sda,
         fpga_scl_io             => dummy_scl,
         fpga_sda_io             => dummy_sda
      );

   -- Milestone M4 re-introduces k2_ps2_mouse here and converts its deltas into
   -- 1351 proportional POT values feeding main_pot1_*/main_pot2_*.  Until then
   -- the socket stays released.
   ps2_mouse_clk_io  <= 'Z';
   ps2_mouse_data_io <= 'Z';


   i_core : entity work.MEGA65_Core
      generic map (
         G_BOARD => "K2_REVB0C"
      )
      port map (
         clk_i                   => clk_100_i,
         main_clk_o              => main_clk,
         main_rst_o              => main_rst,
         qnice_clk_i             => qnice_clk,
         qnice_rst_i             => qnice_rst,
         qnice_dvi_o             => qnice_dvi,
         qnice_video_mode_o      => qnice_video_mode,
         qnice_osm_cfg_scaling_o => qnice_osm_cfg_scaling,
         qnice_scandoubler_o     => qnice_scandoubler,
         qnice_audio_mute_o      => qnice_audio_mute,
         qnice_audio_filter_o    => qnice_audio_filter,
         qnice_zoom_crop_o       => qnice_zoom_crop,
         qnice_ascal_mode_o      => qnice_ascal_mode,
         qnice_ascal_polyphase_o => qnice_ascal_polyphase,
         qnice_ascal_triplebuf_o => qnice_ascal_triplebuf,
         qnice_retro15kHz_o      => qnice_retro15khz,
         qnice_csync_o           => qnice_csync,
         qnice_flip_joyports_o   => qnice_flip_joyports,
         qnice_osm_control_i     => qnice_osm_control_m,
         qnice_gp_reg_i          => qnice_gp_reg,
         qnice_dev_id_i          => qnice_ramrom_dev,
         qnice_dev_addr_i        => qnice_ramrom_addr,
         qnice_dev_data_i        => qnice_ramrom_data_out,
         qnice_dev_data_o        => qnice_ramrom_data_in,
         qnice_dev_ce_i          => qnice_ramrom_ce,
         qnice_dev_we_i          => qnice_ramrom_we,
         qnice_dev_wait_o        => qnice_ramrom_wait,
         hr_clk_i                => hr_clk,
         hr_rst_i                => hr_rst,
         hr_core_write_o         => hr_core_write,
         hr_core_read_o          => hr_core_read,
         hr_core_address_o       => hr_core_address,
         hr_core_writedata_o     => hr_core_writedata,
         hr_core_byteenable_o    => hr_core_byteenable,
         hr_core_burstcount_o    => hr_core_burstcount,
         hr_core_readdata_i      => hr_core_readdata,
         hr_core_readdatavalid_i => hr_core_readdatavalid,
         hr_core_waitrequest_i   => hr_core_waitrequest,
         hr_high_i               => hr_high,
         hr_low_i                => hr_low,
         video_clk_o             => video_clk,
         video_rst_o             => video_rst,
         video_ce_o              => video_ce,
         video_ce_ovl_o          => video_ce_ovl,
         video_red_o             => video_red,
         video_green_o           => video_green,
         video_blue_o            => video_blue,
         video_vs_o              => video_vs,
         video_hs_o              => video_hs,
         video_hblank_o          => video_hblank,
         video_vblank_o          => video_vblank,
         main_reset_m2m_i        => main_reset_m2m or main_qnice_reset or main_rst,
         main_reset_core_i       => main_reset_core or main_qnice_reset,
         main_pause_core_i       => main_qnice_pause,
         main_osm_control_i      => main_osm_control_m,
         main_qnice_gp_reg_i     => main_qnice_gp_reg,
         main_audio_left_o       => main_audio_l,
         main_audio_right_o      => main_audio_r,
         main_kb_key_num_i       => main_key_num,
         main_kb_key_pressed_n_i => main_key_pressed_n,
         main_power_led_o        => main_power_led,
         main_power_led_col_o    => main_power_led_col,
         main_drive_led_o        => main_drive_led,
         main_drive_led_col_o    => main_drive_led_col,
         main_joy_1_up_n_i       => main_joy1_up_n,
         main_joy_1_down_n_i     => main_joy1_down_n,
         main_joy_1_left_n_i     => main_joy1_left_n,
         main_joy_1_right_n_i    => main_joy1_right_n,
         main_joy_1_fire_n_i     => main_joy1_fire_n,
         main_joy_1_up_n_o       => open,
         main_joy_1_down_n_o     => open,
         main_joy_1_left_n_o     => open,
         main_joy_1_right_n_o    => open,
         main_joy_1_fire_n_o     => open,
         main_joy_2_up_n_i       => main_joy2_up_n,
         main_joy_2_down_n_i     => main_joy2_down_n,
         main_joy_2_left_n_i     => main_joy2_left_n,
         main_joy_2_right_n_i    => main_joy2_right_n,
         main_joy_2_fire_n_i     => main_joy2_fire_n,
         main_joy_2_up_n_o       => open,
         main_joy_2_down_n_o     => open,
         main_joy_2_left_n_o     => open,
         main_joy_2_right_n_o    => open,
         main_joy_2_fire_n_o     => open,
         main_pot1_x_i           => main_pot1_x,
         main_pot1_y_i           => main_pot1_y,
         main_pot2_x_i           => main_pot2_x,
         main_pot2_y_i           => main_pot2_y,
         main_rtc_i              => main_rtc,
         iec_reset_n_o           => open,
         iec_atn_n_o             => open,
         iec_clk_en_o            => open,
         iec_clk_n_i             => '1',
         iec_clk_n_o             => open,
         iec_data_en_o           => open,
         iec_data_n_i            => '1',
         iec_data_n_o            => open,
         iec_srq_en_o            => open,
         iec_srq_n_i             => '1',
         iec_srq_n_o             => open,
         cart_en_o               => open,
         cart_phi2_o             => open,
         cart_dotclock_o         => open,
         cart_dma_i              => '1',
         cart_reset_oe_o         => open,
         cart_reset_i            => '1',
         cart_reset_o            => open,
         cart_game_oe_o          => open,
         cart_game_i             => '1',
         cart_game_o             => open,
         cart_exrom_oe_o         => open,
         cart_exrom_i            => '1',
         cart_exrom_o            => open,
         cart_nmi_oe_o           => open,
         cart_nmi_i              => '1',
         cart_nmi_o              => open,
         cart_irq_oe_o           => open,
         cart_irq_i              => '1',
         cart_irq_o              => open,
         cart_roml_oe_o          => open,
         cart_roml_i             => '1',
         cart_roml_o             => open,
         cart_romh_oe_o          => open,
         cart_romh_i             => '1',
         cart_romh_o             => open,
         cart_ctrl_oe_o          => open,
         cart_ba_i               => '1',
         cart_rw_i               => '1',
         cart_io1_i              => '1',
         cart_io2_i              => '1',
         cart_ba_o               => open,
         cart_rw_o               => open,
         cart_io1_o              => open,
         cart_io2_o              => open,
         cart_addr_oe_o          => open,
         cart_a_i                => (others => '1'),
         cart_a_o                => open,
         cart_data_oe_o          => open,
         cart_d_i                => (others => '1'),
         cart_d_o                => open
      );

end architecture synthesis;
