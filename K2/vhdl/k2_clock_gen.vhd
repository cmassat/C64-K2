----------------------------------------------------------------------------------
-- K2 RevB0C board clocks from the exact 40.000 MHz oscillator.
--
-- One MMCM at a 1 GHz VCO provides:
--   100.000 MHz  AExp/M2M system reference
--   333.333 MHz  MIG system clock (matches mig_a.prj InputClkFreq)
--   200.000 MHz  MIG IODELAY reference
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library unisim;
use unisim.vcomponents.all;

entity k2_clock_gen is
   port (
      clk_40_i      : in  std_logic;
      rst_i         : in  std_logic;
      clk_100_o     : out std_logic;
      clk_333_o     : out std_logic;
      clk_200_o     : out std_logic;
      locked_o      : out std_logic
   );
end entity k2_clock_gen;

architecture rtl of k2_clock_gen is

   signal clk_fb      : std_logic;
   signal clk_100_raw : std_logic;
   signal clk_333_raw : std_logic;
   signal clk_200_raw : std_logic;

begin

   i_mmcm : MMCME2_BASE
      generic map (
         BANDWIDTH          => "OPTIMIZED",
         CLKFBOUT_MULT_F    => 25.000,
         CLKIN1_PERIOD      => 25.000,
         CLKOUT0_DIVIDE_F   => 10.000,
         CLKOUT1_DIVIDE     => 3,
         CLKOUT2_DIVIDE     => 5,
         DIVCLK_DIVIDE      => 1,
         STARTUP_WAIT       => false
      )
      port map (
         CLKIN1   => clk_40_i,
         CLKFBIN  => clk_fb,
         CLKFBOUT => clk_fb,
         CLKOUT0  => clk_100_raw,
         CLKOUT1  => clk_333_raw,
         CLKOUT2  => clk_200_raw,
         LOCKED   => locked_o,
         PWRDWN   => '0',
         RST      => rst_i
      );

   i_bufg_100 : BUFG port map (I => clk_100_raw, O => clk_100_o);
   i_bufg_333 : BUFG port map (I => clk_333_raw, O => clk_333_o);
   i_bufg_200 : BUFG port map (I => clk_200_raw, O => clk_200_o);

end architecture rtl;
