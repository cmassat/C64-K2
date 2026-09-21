-- K2 keyboard SK6812Side chain on W24: LOCK, PWR, MEDIA, NETWORK.
-- Evidence: WB_K2_Keyboard_RevA0A schematic and K2 reference
-- RGB_STATUS_LED_Driver_Module (GRB, MSB first; 0.3/0.6 us high).
-- 100 MHz only: 1.25 us per bit, >300 us latch low, about 100 Hz refresh.
-- LOCK and NETWORK are explicitly off; they are not activity indicators.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity k2_status_leds is
   port (
      clk_i          : in  std_logic;
      rst_i          : in  std_logic;
      core_reset_i  : in  std_logic;
      drive_active_i : in  std_logic;
      drive_dirty_i  : in  std_logic;
      serial_o       : out std_logic := '0'
   );
end entity;

architecture rtl of k2_status_leds is
   signal status_meta : std_logic_vector(2 downto 0) := "100";
   signal status_sync : std_logic_vector(2 downto 0) := "100";
   attribute ASYNC_REG : string;
   attribute ASYNC_REG of status_meta, status_sync : signal is "TRUE";
   -- Each status bit is independent. Never synchronize an RGB color bus.
   signal shift       : std_logic_vector(95 downto 0) := (others => '0');
   signal transmitting : boolean := false;
   signal bit_ticks   : natural range 0 to 124 := 0;
   signal bits_left   : natural range 0 to 95 := 95;
   signal gap_ticks   : natural range 0 to 999999 := 30000;
   -- A short disk pulse must remain visible across an LED refresh interval.
   -- This stretches only activity, never a stale "dirty" indication.
   signal activity_hold : natural range 0 to 1999999 := 0;
begin
   process(clk_i)
      variable power_grb, media_grb : std_logic_vector(23 downto 0);
   begin
      if rising_edge(clk_i) then
         status_meta <= core_reset_i & drive_active_i & drive_dirty_i;
         status_sync <= status_meta;
         if rst_i = '1' then
            status_meta <= "100";
            status_sync <= "100";
            transmitting <= false;
            gap_ticks <= 30000;
            bit_ticks <= 0;
            bits_left <= 95;
            shift <= (others => '0');
            serial_o <= '0';
            activity_hold <= 0;
         else
            if status_sync(1) = '1' then
               activity_hold <= 1999999;
            elsif activity_hold > 0 then
               activity_hold <= activity_hold - 1;
            end if;
            if not transmitting then
               serial_o <= '0';
               if gap_ticks = 0 then
                  -- Modest brightness (0x20), GRB wire order.
                  power_grb := x"200000";       -- green: reset released
                  if status_sync(2) = '1' then
                     power_grb := x"000020";    -- blue: reset / ROM load
                  end if;
                  media_grb := x"000000";
                  if status_sync(0) = '1' then
                     media_grb := x"002000";    -- red: pending write-back
                  elsif status_sync(1) = '1' or activity_hold > 0 then
                     media_grb := x"102000";    -- amber: drive activity
                  end if;
                  -- Snapshot all four colors; changes cannot tear a frame.
                  shift <= x"000000" & power_grb & media_grb & x"000000";
                  transmitting <= true;
                  bit_ticks <= 0;
                  bits_left <= 95;
                  serial_o <= '1';
               else
                  gap_ticks <= gap_ticks - 1;
               end if;
            else
               if (shift(95) = '0' and bit_ticks = 29) or
                  (shift(95) = '1' and bit_ticks = 59) then
                  serial_o <= '0';
               end if;
               if bit_ticks = 124 then
                  bit_ticks <= 0;
                  if bits_left = 0 then
                     transmitting <= false;
                     serial_o <= '0';
                     gap_ticks <= 999999;
                  else
                     bits_left <= bits_left - 1;
                     shift <= shift(94 downto 0) & '0';
                     serial_o <= '1';
                  end if;
               else
                  bit_ticks <= bit_ticks + 1;
               end if;
            end if;
         end if;
      end if;
   end process;
end architecture;
