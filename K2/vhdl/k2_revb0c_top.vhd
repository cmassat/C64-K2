----------------------------------------------------------------------------------
-- C64MEGA65 physical shell for Wildbits K2 RevB0C only.
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

entity k2_revb0c_top is
   port (
      COLD_RESETn_io     : inout std_logic;
      CLK_40_000Mhz_0_i  : in    std_logic;
      CLK_24_576Mhz_0_i  : in    std_logic;

      DBG_RX_i           : in    std_logic;
      DBG_TX_o           : out   std_logic;
      DBG_CTSn_o         : out   std_logic;

      PA_io              : inout std_logic_vector(7 downto 0);
      PB_io              : inout std_logic_vector(8 downto 0);
      MECH_OPTICALn_i    : in    std_logic;
      -- Socket pins 1/5: a directly connected PS/2 mouse uses this pair.
      PS2_KB_CLK_io     : inout std_logic;
      PS2_KB_DATA_io    : inout std_logic;
      -- Socket pins 2/6: unused secondary pair for a keyboard/mouse splitter.
      PS2_MS_CLK_io     : inout std_logic;
      PS2_MS_DATA_io    : inout std_logic;

      J1_UP_i            : inout std_logic;
      J1_DOWN_i          : inout std_logic;
      J1_LEFT_i          : inout std_logic;
      J1_RIGHT_i         : inout std_logic;
      J1_BTN0_i          : inout std_logic;
      J0_UP_i            : inout std_logic;
      J0_DOWN_i          : inout std_logic;
      J0_LEFT_i          : inout std_logic;
      J0_RIGHT_i         : inout std_logic;
      J0_BTN0_i          : inout std_logic;

      F_SD0_CD_i         : in    std_logic;
      F_SD0_CLK_o        : out   std_logic;
      F_SD0_CMD_o        : out   std_logic;
      F_SD0_DAT0_i       : in    std_logic;
      F_SD0_DAT3_o       : out   std_logic;
      F_SD1_CLK_o        : out   std_logic;
      F_SD1_CMD_o        : out   std_logic;
      F_SD1_DAT0_i       : in    std_logic;
      F_SD1_DAT3_o       : out   std_logic;

      CODEC_MCLK_o       : out   std_logic;
      CODEC_DAC_BCLK_o   : out   std_logic;
      CODEC_DAC_DAT_o    : out   std_logic;
      CODEC_DAC_LRCK_o   : out   std_logic;
      CODEC_CE_o         : out   std_logic;
      CODEC_CL_o         : out   std_logic;
      CODEC_DI_o         : out   std_logic;

      POWER_LED_o        : out   std_logic;
      SDCARD_LED_o       : out   std_logic;
      STATUS_RGB_3V3_o   : out   std_logic;
      STAT_LED0_o        : out   std_logic;
      STAT_LED1_o        : out   std_logic;

      iHDMI_CEC_io       : inout std_logic;
      iHDMI_SCL_io       : inout std_logic;
      iHDMI_SDA_io       : inout std_logic;
      iHDMI_HPD_i        : in    std_logic;
      -- AA4 is the Restore key input in the current RevB0C pinout.
      -- Its key-down pulse is converted to a logical Help press for the OSM.
      RESTOREn_KEY_i     : in    std_logic;
      iHDMI_Ch0_n        : out   std_logic;
      iHDMI_Ch0_p        : out   std_logic;
      iHDMI_Ch1_n        : out   std_logic;
      iHDMI_Ch1_p        : out   std_logic;
      iHDMI_Ch2_n        : out   std_logic;
      iHDMI_Ch2_p        : out   std_logic;
      iHDMI_CLK_n        : out   std_logic;
      iHDMI_CLK_p        : out   std_logic;

      DDR3_DM            : out   std_logic_vector(1 downto 0);
      DDR3_DQ            : inout std_logic_vector(15 downto 0);
      DDR3_A             : out   std_logic_vector(12 downto 0);
      DDR3_BA            : out   std_logic_vector(2 downto 0);
      DDR3_CASn          : out   std_logic;
      DDR3_RASn          : out   std_logic;
      DDR3_WEn           : out   std_logic;
      DDR3_CKE           : out   std_logic_vector(0 downto 0);
      DDR3_RESn          : out   std_logic;
      DDR3_CLK_n         : out   std_logic_vector(0 downto 0);
      DDR3_CLK_p         : out   std_logic_vector(0 downto 0);
      DDR3_DQS_n         : inout std_logic_vector(1 downto 0);
      DDR3_DQS_p         : inout std_logic_vector(1 downto 0);
      DDR3_ODT           : out   std_logic_vector(0 downto 0);

      -- Explicitly parked legacy CPU and SRAM resources.  SRAM remains free
      -- for a later core-memory expansion without changing the DDR backend.
      C816_CLK_o         : out   std_logic;
      C816_RSTn_io      : inout std_logic;
      C816_RSTn_bis     : out   std_logic;
      -- BQ4802LY is on the legacy CPU bus, NOT the SRAM bus.
      C816_BE_o         : out   std_logic;
      C816_A_io         : inout std_logic_vector(3 downto 0);
      C816_D_io         : inout std_logic_vector(7 downto 0);
      C816_RWn_io       : inout std_logic;
      BUS_OEn_o         : out   std_logic;
      MEM_A_o           : out   std_logic_vector(20 downto 0);
      MEM_D_io          : inout std_logic_vector(15 downto 0);
      MEM_CSn_o         : out   std_logic;
      MEM_OEn_o         : out   std_logic;
      MEM_WEn_o         : out   std_logic;
      MEM_LBn_o         : out   std_logic;
      MEM_UBn_o         : out   std_logic;
      CS_EXP256K2n_o    : out   std_logic;
      CS_FLASHn_o       : out   std_logic;
      CS_RTCn_o         : out   std_logic;
      FLASH_WRn_o       : out   std_logic;
      RST_FLASHn_o      : out   std_logic;

      -- Built-in ST7789 identification display (240x280 visible pixels).
      LCD_CSn_o         : out   std_logic;
      LCD_RSTn_o        : out   std_logic;
      LCD_BL_o          : out   std_logic;
      LCD_DC_o          : out   std_logic;
      LCD_DIN_o         : out   std_logic;
      LCD_SCLK_o        : out   std_logic;

      -- Keep non-participating peripherals electrically quiet.
      NET_CSn_o         : out   std_logic;
      NET_RDn_o         : out   std_logic;
      NET_WRn_o         : out   std_logic;
      NET_RSTn_o        : out   std_logic;
      WIFI_SPI_CS0n_o   : out   std_logic;
      SPLASH_SPI_CS1n_o : out   std_logic;
      WIFI_RSTn_o       : out   std_logic;
      PER_RSTn_o        : out   std_logic;
      SAM2695_RSTn_o    : out   std_logic;
      WAVETABLE_RST_o   : out   std_logic;
      SUPERVISOR_CSn_o  : out   std_logic
   );
end entity k2_revb0c_top;

architecture synthesis of k2_revb0c_top is
   attribute DONT_TOUCH : string;
   attribute DONT_TOUCH of i_rtc_rw : label is "TRUE";
   signal rtc_100 : std_logic_vector(64 downto 0);
   signal rtc_owned : std_logic;
   signal rtc_address : std_logic_vector(3 downto 0);
   signal injected_keys_100 : std_logic_vector(79 downto 0) := (others => '1');
   signal system_uart_rx, system_uart_tx : std_logic;

   component k2_lcd_splash is
      port (
         clk_i, reset_i : in std_logic;
         temperature_raw_i : in std_logic_vector(11 downto 0);
         temperature_available_i, temperature_heartbeat_i : in std_logic;
         lcd_bl_o, lcd_cs_n_o, lcd_dc_o, lcd_mosi_o : out std_logic;
         lcd_sclk_o, lcd_reset_n_o : out std_logic
      );
   end component;

   component DDR3_CTRL is
      port (
         ddr3_dq            : inout std_logic_vector(15 downto 0);
         ddr3_dqs_n         : inout std_logic_vector(1 downto 0);
         ddr3_dqs_p         : inout std_logic_vector(1 downto 0);
         ddr3_addr          : out   std_logic_vector(12 downto 0);
         ddr3_ba            : out   std_logic_vector(2 downto 0);
         ddr3_ras_n         : out   std_logic;
         ddr3_cas_n         : out   std_logic;
         ddr3_we_n          : out   std_logic;
         ddr3_reset_n       : out   std_logic;
         ddr3_ck_p          : out   std_logic_vector(0 downto 0);
         ddr3_ck_n          : out   std_logic_vector(0 downto 0);
         ddr3_cke           : out   std_logic_vector(0 downto 0);
         ddr3_dm            : out   std_logic_vector(1 downto 0);
         ddr3_odt           : out   std_logic_vector(0 downto 0);
         sys_clk_i          : in    std_logic;
         clk_ref_i          : in    std_logic;
         app_addr           : in    std_logic_vector(26 downto 0);
         app_cmd            : in    std_logic_vector(2 downto 0);
         app_en             : in    std_logic;
         app_wdf_data       : in    std_logic_vector(63 downto 0);
         app_wdf_end        : in    std_logic;
         app_wdf_mask       : in    std_logic_vector(7 downto 0);
         app_wdf_wren       : in    std_logic;
         app_rd_data        : out   std_logic_vector(63 downto 0);
         app_rd_data_end    : out   std_logic;
         app_rd_data_valid  : out   std_logic;
         app_rdy            : out   std_logic;
         app_wdf_rdy        : out   std_logic;
         app_sr_req         : in    std_logic;
         app_ref_req        : in    std_logic;
         app_zq_req         : in    std_logic;
         app_sr_active      : out   std_logic;
         app_ref_ack        : out   std_logic;
         app_zq_ack         : out   std_logic;
         ui_clk             : out   std_logic;
         ui_clk_sync_rst    : out   std_logic;
         init_calib_complete: out   std_logic;
         device_temp        : out   std_logic_vector(11 downto 0);
         sys_rst            : in    std_logic
      );
   end component;

   signal board_reset       : std_logic;
   signal reset_n           : std_logic;
   signal clk_locked        : std_logic;
   signal clk_100           : std_logic;
   signal clk_333           : std_logic;
   signal clk_200           : std_logic;
   signal mem_clk           : std_logic;
   signal mem_rst           : std_logic;
   signal mem_calib_done    : std_logic;
   signal mem_temperature, lcd_temperature : std_logic_vector(11 downto 0);
   signal lcd_temperature_available, lcd_temperature_heartbeat : std_logic;
   signal key_state_n       : std_logic_vector(79 downto 0);
   signal power_led         : std_logic;
   signal drive_led         : std_logic;
   signal power_led_col     : std_logic_vector(23 downto 0);
   signal drive_led_col     : std_logic_vector(23 downto 0);
   signal audio_clk         : std_logic;
   signal audio_reset       : std_logic;
   signal audio_left        : signed(15 downto 0);
   signal audio_right       : signed(15 downto 0);
   signal mem_app_addr      : std_logic_vector(26 downto 0);
   signal mem_app_cmd       : std_logic_vector(2 downto 0);
   signal mem_app_en        : std_logic;
   signal mem_app_rdy       : std_logic;
   signal mem_app_wdf_data  : std_logic_vector(63 downto 0);
   signal mem_app_wdf_end   : std_logic;
   signal mem_app_wdf_mask  : std_logic_vector(7 downto 0);
   signal mem_app_wdf_wren  : std_logic;
   signal mem_app_wdf_rdy   : std_logic;
   signal mem_app_rd_data   : std_logic_vector(63 downto 0);
   signal mem_app_rd_valid  : std_logic;
   signal mem_app_rd_end    : std_logic;

begin
   PS2_MS_CLK_io <= 'Z';
   PS2_MS_DATA_io <= 'Z';


   COLD_RESETn_io <= 'Z';
   -- The board reset net is weakly pulled high and can therefore resolve to
   -- 'H'.  Convert it to ordinary logic before it enters the MMCM or design.
   board_reset <= '1' when COLD_RESETn_io = '0' else '0';
   reset_n     <= '1' when board_reset = '0' and clk_locked = '1' else '0';

   i_clocks : entity work.k2_clock_gen
      port map (
         clk_40_i  => CLK_40_000Mhz_0_i,
         rst_i     => board_reset,
         clk_100_o => clk_100,
         clk_333_o => clk_333,
         clk_200_o => clk_200,
         locked_o  => clk_locked
      );

   i_mig : DDR3_CTRL
      port map (
         ddr3_dq             => DDR3_DQ,
         ddr3_dqs_n          => DDR3_DQS_n,
         ddr3_dqs_p          => DDR3_DQS_p,
         ddr3_addr           => DDR3_A,
         ddr3_ba             => DDR3_BA,
         ddr3_ras_n          => DDR3_RASn,
         ddr3_cas_n          => DDR3_CASn,
         ddr3_we_n           => DDR3_WEn,
         ddr3_reset_n        => DDR3_RESn,
         ddr3_ck_p           => DDR3_CLK_p,
         ddr3_ck_n           => DDR3_CLK_n,
         ddr3_cke            => DDR3_CKE,
         ddr3_dm             => DDR3_DM,
         ddr3_odt            => DDR3_ODT,
         sys_clk_i           => clk_333,
         clk_ref_i           => clk_200,
         app_addr            => mem_app_addr,
         app_cmd             => mem_app_cmd,
         app_en              => mem_app_en,
         app_wdf_data        => mem_app_wdf_data,
         app_wdf_end         => mem_app_wdf_end,
         app_wdf_mask        => mem_app_wdf_mask,
         app_wdf_wren        => mem_app_wdf_wren,
         app_rd_data         => mem_app_rd_data,
         app_rd_data_end     => mem_app_rd_end,
         app_rd_data_valid   => mem_app_rd_valid,
         app_rdy             => mem_app_rdy,
         app_wdf_rdy         => mem_app_wdf_rdy,
         app_sr_req          => '0',
         app_ref_req         => '0',
         app_zq_req          => '0',
         app_sr_active       => open,
         app_ref_ack         => open,
         app_zq_ack          => open,
         ui_clk              => mem_clk,
         ui_clk_sync_rst     => mem_rst,
         init_calib_complete => mem_calib_done,
         device_temp         => mem_temperature,
         sys_rst             => reset_n
      );

   i_keyboard : entity work.k2_keyboard_matrix
      port map (
         clk_i            => clk_100,
         rst_i            => not reset_n,
         restore_n_i      => RESTOREn_KEY_i,
         pa_io            => PA_io,
         pb_io            => PB_io,
         key_state_n_o    => key_state_n
      );

   i_system : entity work.k2_c64_system
      port map (
         clk_100_i               => clk_100,
         rtc_100_i               => rtc_100,
         reset_n_i               => reset_n,
         uart_rxd_i              => system_uart_rx,
         uart_txd_o              => system_uart_tx,
         tmds_data_p_o(0)        => iHDMI_Ch0_p,
         tmds_data_p_o(1)        => iHDMI_Ch1_p,
         tmds_data_p_o(2)        => iHDMI_Ch2_p,
         tmds_data_n_o(0)        => iHDMI_Ch0_n,
         tmds_data_n_o(1)        => iHDMI_Ch1_n,
         tmds_data_n_o(2)        => iHDMI_Ch2_n,
         tmds_clk_p_o            => iHDMI_CLK_p,
         tmds_clk_n_o            => iHDMI_CLK_n,
         hdmi_scl_io             => iHDMI_SCL_io,
         hdmi_sda_io             => iHDMI_SDA_io,
         sd_reset_o              => F_SD0_DAT3_o,
         sd_clk_o                => F_SD0_CLK_o,
         sd_mosi_o               => F_SD0_CMD_o,
         sd_miso_i               => F_SD0_DAT0_i,
         sd_cd_i                 => F_SD0_CD_i,
         sd2_reset_o             => F_SD1_DAT3_o,
         sd2_clk_o               => F_SD1_CLK_o,
         sd2_mosi_o              => F_SD1_CMD_o,
         sd2_miso_i              => F_SD1_DAT0_i,
         sd2_cd_i                => '0',
         key_state_n_i           => key_state_n and injected_keys_100,
         ps2_mouse_clk_io        => PS2_KB_CLK_io,
         ps2_mouse_data_io       => PS2_KB_DATA_io,
         joy_1_up_n_i            => J1_UP_i,
         joy_1_down_n_i          => J1_DOWN_i,
         joy_1_left_n_i          => J1_LEFT_i,
         joy_1_right_n_i         => J1_RIGHT_i,
         joy_1_fire_n_i          => J1_BTN0_i,
         joy_2_up_n_i            => J0_UP_i,
         joy_2_down_n_i          => J0_DOWN_i,
         joy_2_left_n_i          => J0_LEFT_i,
         joy_2_right_n_i         => J0_RIGHT_i,
         joy_2_fire_n_i          => J0_BTN0_i,
         power_led_o             => power_led,
         drive_led_o             => drive_led,
         power_led_col_o         => power_led_col,
         drive_led_col_o         => drive_led_col,
         audio_clk_o             => audio_clk,
         audio_reset_o           => audio_reset,
         audio_left_o            => audio_left,
         audio_right_o           => audio_right,
         mem_clk_i               => mem_clk,
         mem_rst_i               => mem_rst,
         mem_calib_done_i        => mem_calib_done,
         mem_app_addr_o          => mem_app_addr,
         mem_app_cmd_o           => mem_app_cmd,
         mem_app_en_o            => mem_app_en,
         mem_app_rdy_i           => mem_app_rdy,
         mem_app_wdf_data_o      => mem_app_wdf_data,
         mem_app_wdf_end_o       => mem_app_wdf_end,
         mem_app_wdf_mask_o      => mem_app_wdf_mask,
         mem_app_wdf_wren_o      => mem_app_wdf_wren,
         mem_app_wdf_rdy_i       => mem_app_wdf_rdy,
         mem_app_rd_data_i       => mem_app_rd_data,
         mem_app_rd_data_valid_i => mem_app_rd_valid,
         mem_app_rd_data_end_i   => mem_app_rd_end
      );

   i_codec : entity work.k2_codec_audio
      port map (
         clk_100_i     => clk_100,
         clk_24_576_i  => CLK_24_576Mhz_0_i,
         rst_i         => not reset_n,
         audio_clk_i   => audio_clk,
         audio_reset_i => audio_reset,
         audio_left_i  => audio_left,
         audio_right_i => audio_right,
         codec_mclk_o  => CODEC_MCLK_o,
         codec_bclk_o  => CODEC_DAC_BCLK_o,
         codec_lrclk_o => CODEC_DAC_LRCK_o,
         codec_data_o  => CODEC_DAC_DAT_o,
         codec_ce_o    => CODEC_CE_o,
         codec_cl_o    => CODEC_CL_o,
         codec_di_o    => CODEC_DI_o
      );

   -- Direct DB9 inputs; the core never drives joystick directions/fire.
   J1_UP_i    <= 'Z'; J1_DOWN_i  <= 'Z'; J1_LEFT_i <= 'Z'; J1_RIGHT_i <= 'Z'; J1_BTN0_i <= 'Z';
   J0_UP_i    <= 'Z'; J0_DOWN_i  <= 'Z'; J0_LEFT_i <= 'Z'; J0_RIGHT_i <= 'Z'; J0_BTN0_i <= 'Z';

   iHDMI_CEC_io   <= 'Z';
   -- The diagnostic (trace) UART variant from AExp-K2 is not ported yet; the
   -- QNICE console owns this UART.
   injected_keys_100 <= (others => '1');
   system_uart_rx <= DBG_RX_i;
   DBG_TX_o <= system_uart_tx;
   DBG_CTSn_o     <= '1';
   POWER_LED_o    <= power_led;
   -- The discrete LEDs are separate from the keyboard's serial RGB chain.
   -- Core RGB status is blue/green for reset/run and yellow/green for dirty/
   -- active. Use the distinct blue/red bits as independent CDC status flags.
   i_status_leds : entity work.k2_status_leds
      port map (
         clk_i => clk_100, rst_i => not reset_n,
         core_reset_i => power_led_col(0),
         drive_active_i => drive_led, drive_dirty_i => drive_led_col(16),
         serial_o => STATUS_RGB_3V3_o
      );
   SDCARD_LED_o   <= drive_led;
   STAT_LED0_o    <= mem_calib_done;
   STAT_LED1_o    <= not reset_n;

   -- Reuse MIG's existing XADC, leaving its DDR3 monitoring untouched.
   i_temperature_source : entity work.k2_temperature_source
      port map (mem_clk_i => mem_clk, mem_reset_i => mem_rst,
                calibrated_i => mem_calib_done, device_temp_i => mem_temperature,
                clk_i => clk_100, raw_o => lcd_temperature,
                available_o => lcd_temperature_available,
                heartbeat_o => lcd_temperature_heartbeat);

   -- LCD identification is independent of ROM loading and core
   -- warm resets. The compressed image lives in LUT ROM, not scarce BRAM.
   i_lcd : k2_lcd_splash
      port map (
         clk_i => clk_100, reset_i => not reset_n,
         temperature_raw_i => lcd_temperature,
         temperature_available_i => lcd_temperature_available,
         temperature_heartbeat_i => lcd_temperature_heartbeat,
         lcd_bl_o => LCD_BL_o, lcd_cs_n_o => LCD_CSn_o,
         lcd_dc_o => LCD_DC_o, lcd_mosi_o => LCD_DIN_o,
         lcd_sclk_o => LCD_SCLK_o, lcd_reset_n_o => LCD_RSTn_o
      );

   -- Park resources which are deliberately reserved for later increments.
   C816_CLK_o      <= '0';
   C816_RSTn_io    <= '0';
   C816_RSTn_bis   <= '0';
   -- BE low disables physical 65C816 address/data/RW drivers. Wait 1 ms
   -- before driving address/RW; CS/OE stay high throughout this guard time.
   C816_BE_o       <= '0';
   C816_A_io       <= rtc_address when rtc_owned = '1' else (others => 'Z');
   -- An inferred conditional '1'/Z output can become I=not(T). Although
   -- logically equivalent, unequal I/T delays could pulse WE at reset.
   -- Keep a literal high on the primitive's I pin: electrically read-only.
   i_rtc_rw : OBUFT
      port map (I => '1', T => not rtc_owned, O => C816_RWn_io);
   C816_D_io       <= (others => 'Z');
   i_rtc : entity work.k2_rtc
      port map (clk_i => clk_100, rst_i => not reset_n,
                data_i => C816_D_io, address_o => rtc_address,
                bus_owned_o => rtc_owned, cs_n_o => CS_RTCn_o,
                oe_n_o => BUS_OEn_o, rtc_o => rtc_100, hardware_valid_o => open);
   MEM_A_o         <= (others => '0');
   MEM_D_io        <= (others => 'Z');
   MEM_CSn_o       <= '1';
   MEM_OEn_o       <= '1';
   MEM_WEn_o       <= '1';
   MEM_LBn_o       <= '1';
   MEM_UBn_o       <= '1';
   CS_EXP256K2n_o  <= '1';
   CS_FLASHn_o     <= '1';
   FLASH_WRn_o     <= '1';
   RST_FLASHn_o    <= '1';

   NET_CSn_o         <= '1';
   NET_RDn_o         <= '1';
   NET_WRn_o         <= '1';
   NET_RSTn_o        <= '0';
   WIFI_SPI_CS0n_o   <= '1';
   SPLASH_SPI_CS1n_o <= '1';
   WIFI_RSTn_o       <= '0';
   PER_RSTn_o        <= '0';
   SAM2695_RSTn_o    <= '0';
   WAVETABLE_RST_o   <= '1';
   SUPERVISOR_CSn_o  <= '1';

end architecture synthesis;
