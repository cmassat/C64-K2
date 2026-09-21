library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Passive fan-out of MIG's public UI-clock-domain temperature output.
-- No changes to MIG's XADC sequencing, DRP ownership or PHY compensation.
entity k2_temperature_source is
   port (
      mem_clk_i, mem_reset_i, calibrated_i : in std_logic;
      device_temp_i : in std_logic_vector(11 downto 0);
      clk_i : in std_logic;
      raw_o : out std_logic_vector(11 downto 0);
      available_o, heartbeat_o : out std_logic
   );
end entity;
architecture rtl of k2_temperature_source is
   signal heartbeat_count : unsigned(15 downto 0) := (others => '0');
   signal heartbeat : std_logic := '0';
   signal source_data, dest_data : std_logic_vector(13 downto 0);
begin
   process(mem_clk_i)
   begin
      if rising_edge(mem_clk_i) then
         if mem_reset_i = '1' then
            heartbeat_count <= (others => '0'); heartbeat <= '0';
         else
            heartbeat_count <= heartbeat_count + 1;
            if heartbeat_count = 65535 then heartbeat <= not heartbeat; end if;
         end if;
      end if;
   end process;
   -- Toggle every 393 us at the 166.667 MHz UI clock; 10 ms destination
   -- watchdog also catches a stopped source clock without a reset edge.
   source_data <= heartbeat & (calibrated_i and not mem_reset_i) & device_temp_i;
   i_cdc : entity work.cdc_stable
      generic map (G_DATA_SIZE => 14, G_REGISTER_SRC => true)
      port map (src_clk_i => mem_clk_i, src_data_i => source_data,
                dst_clk_i => clk_i, dst_data_o => dest_data);
   raw_o <= dest_data(11 downto 0);
   available_o <= dest_data(12);
   heartbeat_o <= dest_data(13);
end architecture;
