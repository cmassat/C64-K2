-- RESTORE pulse -> logical Help -> QNICE menu bit regression.
library ieee;
use ieee.std_logic_1164.all;
library std;
use std.env.all;

entity tb_k2_restore is
end entity;

architecture test of tb_k2_restore is
   -- Accelerated wall time: 1000 cycles still represent the 100 ms press.
   constant C_PERIOD : time := 10 ns;
   signal clk       : std_logic := '0';
   signal main_clk  : std_logic := '0';
   signal rst       : std_logic := '1';
   signal restore_n : std_logic := '1';
   signal pa        : std_logic_vector(7 downto 0);
   signal pb        : std_logic_vector(8 downto 0) := (others => '0');
   signal pressed   : std_logic_vector(71 downto 0) := (others => '0');
   signal extra_pb8 : std_logic := '0';
   signal keys      : std_logic_vector(79 downto 0);
   signal qkeys     : std_logic_vector(15 downto 0);
   signal events    : natural := 0;
   signal key_num   : integer range 0 to 79;
   signal key_n     : std_logic;
   signal reset_seen : boolean := false;
begin
   clk <= not clk after C_PERIOD / 2;
   main_clk <= not main_clk after 7 ns;

   dut : entity work.k2_keyboard_matrix
      generic map (G_CLK_SPEED => 10_000, G_ROW_HZ => 1000)
      port map (clk_i => clk, rst_i => rst,
                restore_n_i => restore_n, pa_io => pa, pb_io => pb,
                key_state_n_o => keys);

   adapter : entity work.k2_m2m_keyb
      port map (clk_main_i => main_clk, clk_main_speed_i => 10_000,
                key_state_n_i => keys, enable_core_i => '0',
                key_num_o => key_num, key_pressed_n_o => key_n,
                qnice_keys_n_o => qkeys);

   optics : process(all)
      variable columns : std_logic_vector(8 downto 0);
   begin
      columns := (others => '0');
      for row in 0 to 7 loop
         if pa(row) = 'Z' then
            columns := columns or pressed(row*9+8 downto row*9);
         end if;
      end loop;
      columns(8) := columns(8) or extra_pb8;
      pb <= columns;
   end process;
   reset_delivery : process(main_clk)
   begin
      if rising_edge(main_clk) then
         assert keys(67) = '1' or keys(75) = '1'
            report "RESTORE went to both menu and reset" severity failure;
         if key_num = 75 and key_n = '0' then reset_seen <= true; end if;
         if key_num /= 75 then
            assert key_n = '1' report "Ordinary key bypassed OSM gating" severity failure;
         end if;
      end if;
   end process;

   -- Model KEYB$SCAN's edge detector at a slower polling cadence. It must
   -- see one event, even with the Amiga's keyboard disabled by the OSM.
   poll : process
      variable previous_n : std_logic := '1';
   begin
      for i in 1 to 25 loop
         wait until rising_edge(main_clk);
      end loop;
      if qkeys(7) = '0' and previous_n = '1' then
         events <= events + 1;
      end if;
      previous_n := qkeys(7);
   end process;

   stimulus : process
      procedure ticks(n : positive) is
      begin
         wait for n * C_PERIOD;
      end procedure;
      variable started : time;
   begin
      ticks(10);
      rst <= '0';
      ticks(220);
      assert keys(67) = '1' and events = 0 severity failure;

      -- Short asynchronous key-down, followed by bounce. No physical key-up
      -- event is needed: returning the electrical pulse to idle suffices.
      wait for 3 ns;
      restore_n <= '0';
      wait until keys(67) = '0';
      started := now;
      restore_n <= '1';
      ticks(10);
      restore_n <= '0';
      ticks(5);
      restore_n <= '1';
      wait until keys(67) = '1';
      assert now - started = 1000 * C_PERIOD
         report "RESTORE press duration changed/retriggered" severity failure;
      ticks(220);
      assert events = 1 report "Short pulse lost or bounce repeated" severity failure;

      -- Long low input still auto-releases and must not repeat.
      restore_n <= '0';
      ticks(2500);
      assert keys(67) = '1' and events = 2
         report "Held RESTORE stuck or repeated" severity failure;
      restore_n <= '1';
      ticks(50);
      restore_n <= '0';
      ticks(250);
      assert events = 2 report "Rearmed without quiet interval" severity failure;
      restore_n <= '1';
      ticks(220);
      restore_n <= '0';
      ticks(6);
      restore_n <= '1';
      ticks(1250);
      assert events = 3 report "Second deliberate press lost" severity failure;

      -- PB8 no longer aliases either extension position to Help.
      extra_pb8 <= '1';
      ticks(300);
      assert keys(67) = '1' and events = 3
         report "PB8 still opens the menu" severity failure;
      extra_pb8 <= '0';

      -- Reset while pressed clears the synthetic state; a low input held
      -- across reset cannot create a phantom new event.
      restore_n <= '0';
      ticks(100);
      assert events = 4 severity failure;
      rst <= '1';
      ticks(10);
      assert keys(67) = '1' report "Reset did not release Help" severity failure;
      rst <= '0';
      ticks(1500);
      assert events = 4 report "Phantom press after reset" severity failure;
      restore_n <= '1';
      ticks(220);
      restore_n <= '0';
      ticks(6);
      restore_n <= '1';
      ticks(1250);
      assert events = 5 report "Did not rearm after reset" severity failure;

      -- Hold CTRL + /F first, then RESTORE. Releasing modifiers immediately
      -- must not redirect the remaining stretched press into the menu.
      pressed(65) <= '1'; -- CTRL PA7/PB2
      pressed(68) <= '1'; -- /F PA7/PB5
      ticks(300);
      restore_n <= '0'; ticks(6); restore_n <= '1';
      assert keys(75) = '0' and keys(67) = '1' severity failure;
      pressed <= (others => '0');
      ticks(500);
      assert keys(75) = '0' and keys(67) = '1' and events = 5 severity failure;
      assert reset_seen report "OSM gating swallowed qualified reset" severity failure;
      ticks(750);
      assert keys(75) = '1' and events = 5 severity failure;

      -- Reverse order is deliberately NOT reset: modifiers added after the
      -- RESTORE event cannot retroactively change its destination.
      restore_n <= '0'; ticks(6); restore_n <= '1';
      pressed(65) <= '1'; pressed(68) <= '1';
      ticks(500);
      assert keys(67) = '0' and keys(75) = '1' and events = 6 severity failure;
      ticks(750);

      -- Each modifier alone still allows ordinary RESTORE menu operation.
      pressed(68) <= '0'; ticks(300);
      restore_n <= '0'; ticks(6); restore_n <= '1'; ticks(1250);
      assert events = 7 and keys(75) = '1' severity failure;
      pressed(65) <= '0'; pressed(68) <= '1'; ticks(300);
      restore_n <= '0'; ticks(6); restore_n <= '1'; ticks(1250);
      assert events = 8 and keys(75) = '1' severity failure;
      pressed <= (others => '0'); ticks(300);

      -- Fn is neither QNICE Escape nor an opener; top-left arrow is Escape.
      pressed(70) <= '1'; ticks(300);
      assert qkeys = x"FFFF" report "Fn leaked into menu navigation" severity failure;
      pressed(70) <= '0'; pressed(64) <= '1'; ticks(300);
      assert qkeys = x"FFBF" report "Top-left Escape not routed to QNICE" severity failure;

      report "PASS: RESTORE pulse, bounce, hold, rearm, reset/menu separation, modifier order, OSM gating and Escape";
      finish;
   end process;

   watchdog : process
   begin
      wait for 1 ms;
      assert false report "RESTORE test timed out" severity failure;
   end process;
end architecture;
