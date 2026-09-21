library ieee;
use ieee.std_logic_1164.all;
library std;
use std.env.all;

entity tb_k2_status_leds is end entity;
architecture test of tb_k2_status_leds is
   signal clk : std_logic := '0';
   signal rst : std_logic := '1';
   signal core_reset : std_logic := '1';
   signal active, dirty : std_logic := '0';
   signal serial : std_logic;
begin
   clk <= not clk after 5 ns;
   dut : entity work.k2_status_leds
      port map (clk, rst, core_reset, active, dirty, serial);

   stimulus : process
      variable previous_end : time := 0 ns;
      procedure frame(expected : std_logic_vector(95 downto 0);
                      change_midframe : boolean := false) is
         variable value : std_logic_vector(95 downto 0);
         variable start_bit, previous_start, high_time : time;
      begin
         for bit_index in 95 downto 0 loop
            wait until rising_edge(serial);
            start_bit := now;
            if bit_index = 95 then
               assert now - previous_end >= 300 us
                  report "LED latch interval too short" severity failure;
            else
               assert now - previous_start = 1250 ns
                  report "LED bit period is not 1.25 us" severity failure;
            end if;
            previous_start := now;
            wait until falling_edge(serial);
            high_time := now - start_bit;
            assert high_time = 300 ns or high_time = 600 ns
               report "Invalid SK6812 pulse width" severity failure;
            if high_time = 600 ns then value(bit_index) := '1';
            else value(bit_index) := '0'; end if;
            if change_midframe and bit_index = 70 then dirty <= '1'; end if;
         end loop;
         previous_end := now;
         assert value = expected report "Wrong LED color/order or torn frame"
            severity failure;
      end procedure;
   begin
      wait for 40 ns;
      rst <= '0';
      frame(x"000000000020000000000000"); -- LOCK off, PWR blue, MEDIA/NET off
      core_reset <= '0';
      frame(x"000000200000000000000000"); -- PWR green
      active <= '1';
      frame(x"000000200000102000000000"); -- MEDIA amber
      active <= '0'; dirty <= '1';
      frame(x"000000200000002000000000"); -- red: dirty wins without activity
      dirty <= '0';
      frame(x"000000200000000000000000"); -- hold has expired after 2 frames
      core_reset <= '1';
      frame(x"000000000020000000000000", true); -- mid-frame dirty cannot tear
      frame(x"000000000020002000000000"); -- new state in next frame

      -- Interrupt a frame: output must go low, then resend a complete frame
      -- after the latch interval. No partial frame may survive board reset.
      wait until rising_edge(serial);
      wait for 100 ns;
      rst <= '1';
      wait for 20 ns;
      assert serial = '0' severity failure;
      dirty <= '0'; active <= '0'; core_reset <= '0';
      previous_end := now;
      rst <= '0';
      frame(x"000000200000000000000000");
      report "PASS: LED GRB order, colors, dirty priority, timing, snapshot and reset";
      finish;
   end process;
   watchdog : process
   begin
      wait for 100 ms;
      assert false report "LED test timed out" severity failure;
   end process;
end architecture;
