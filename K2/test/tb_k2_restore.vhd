-- RESTORE pulse routing regression: bare RESTORE -> slot 75 (the C64 NMI),
-- C= + RESTORE -> slot 67 (Help) -> the QNICE menu-open bit.
--
-- Retargeted from AExp-K2, where the destinations were the other way round
-- (bare RESTORE opened the menu, CTRL + /F + RESTORE requested a reset).  The
-- C64 needs slot 75 for its own NMI, and the key AExp calls Fn is the RUN/STOP
-- keycap, so RUN/STOP must NOT qualify the chord -- otherwise the C64's own
-- RUN/STOP+RESTORE warm reset would never reach the core.
library ieee;
use ieee.std_logic_1164.all;
library std;
use std.env.all;

entity tb_k2_restore is
end entity;

architecture test of tb_k2_restore is
   -- Accelerated wall time: 1000 cycles still represent the 100 ms press.
   constant C_PERIOD : time := 10 ns;

   -- Physical optical-matrix cells, row*9 + column.
   constant C_CELL_ESC      : natural := 7*9 + 1; -- top-left arrow -> slot 57
   constant C_CELL_CTRL     : natural := 7*9 + 2; -- CTRL           -> slot 58
   constant C_CELL_MEGA     : natural := 7*9 + 5; -- C= (/F logo)   -> slot 61
   constant C_CELL_RUN_STOP : natural := 7*9 + 7; -- RUN/STOP       -> slot 63

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
begin
   clk <= not clk after C_PERIOD / 2;
   main_clk <= not main_clk after 7 ns;

   dut : entity work.k2_keyboard_matrix
      generic map (G_CLK_SPEED => 10_000, G_ROW_HZ => 1000)
      port map (clk_i => clk, rst_i => rst,
                restore_n_i => restore_n, pa_io => pa, pb_io => pb,
                key_state_n_o => keys);

   -- enable_core_i = '0' models the OSM being open, with the core's keyboard
   -- disabled.  Nothing may reach the core in that state.
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

   invariants : process(main_clk)
   begin
      if rising_edge(main_clk) then
         assert keys(67) = '1' or keys(75) = '1'
            report "RESTORE reached both the menu and the NMI" severity failure;
         -- AExp exempted slot 75 from OSM gating for its reset request.  Here
         -- slot 75 is the C64 NMI, so no key at all may bypass the gate.
         assert key_n = '1'
            report "Key " & integer'image(key_num) & " bypassed OSM gating"
            severity failure;
      end if;
   end process;

   -- Model KEYB$SCAN's edge detector at a slower polling cadence.
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
      procedure tap_restore is
      begin
         restore_n <= '0'; ticks(6); restore_n <= '1';
      end procedure;
      variable started : time;
   begin
      ticks(10);
      rst <= '0';
      ticks(220);
      assert keys(67) = '1' and keys(75) = '1' and events = 0 severity failure;

      ------------------------------------------------------------------
      -- Bare RESTORE is the C64 NMI, never the menu.
      -- Short asynchronous key-down followed by bounce; no physical key-up
      -- event is needed, returning the electrical pulse to idle suffices.
      ------------------------------------------------------------------
      wait for 3 ns;
      restore_n <= '0';
      wait until keys(75) = '0';
      started := now;
      restore_n <= '1';
      ticks(10);
      restore_n <= '0';
      ticks(5);
      restore_n <= '1';
      assert keys(67) = '1' report "Bare RESTORE opened the menu" severity failure;
      wait until keys(75) = '1';
      assert now - started = 1000 * C_PERIOD
         report "RESTORE press duration changed/retriggered" severity failure;
      ticks(220);
      assert events = 0 report "Bare RESTORE produced a menu event" severity failure;

      -- A long low input still auto-releases and must not repeat.
      restore_n <= '0';
      ticks(2500);
      assert keys(75) = '1' and keys(67) = '1'
         report "Held RESTORE stuck or repeated" severity failure;

      -- Rearming requires a quiet high interval.
      restore_n <= '1';
      ticks(50);
      restore_n <= '0';
      ticks(250);
      assert keys(75) = '1' report "Rearmed without quiet interval" severity failure;
      restore_n <= '1';
      ticks(220);

      ------------------------------------------------------------------
      -- C= + RESTORE opens the menu, and only that chord does.
      ------------------------------------------------------------------
      pressed(C_CELL_MEGA) <= '1';
      ticks(300);
      tap_restore;
      ticks(50);
      assert keys(67) = '0' and keys(75) = '1'
         report "C= + RESTORE did not reach the menu" severity failure;
      -- Releasing the modifier mid-press must not redirect the remaining
      -- stretched press: the destination is latched at the leading edge.
      pressed <= (others => '0');
      ticks(500);
      assert keys(67) = '0' and keys(75) = '1'
         report "Releasing C= redirected the stretched press" severity failure;
      ticks(750);
      assert keys(67) = '1' and events = 1
         report "Menu event lost or repeated" severity failure;

      -- Reverse order: modifiers added after the event cannot retroactively
      -- change its destination.
      tap_restore;
      pressed(C_CELL_MEGA) <= '1';
      ticks(500);
      assert keys(75) = '0' and keys(67) = '1' and events = 1
         report "Late C= redirected RESTORE into the menu" severity failure;
      pressed <= (others => '0');
      ticks(750);

      ------------------------------------------------------------------
      -- The regression that protects the C64's own warm reset: RUN/STOP is
      -- NOT a menu qualifier, so RUN/STOP + RESTORE still reaches slot 75.
      -- CTRL is not one either (AExp used CTRL + /F for its reset chord).
      ------------------------------------------------------------------
      pressed(C_CELL_RUN_STOP) <= '1';
      ticks(300);
      tap_restore;
      ticks(500);
      assert keys(75) = '0' and keys(67) = '1' and events = 1
         report "RUN/STOP + RESTORE was stolen by the menu" severity failure;
      pressed <= (others => '0');
      ticks(750);

      pressed(C_CELL_CTRL) <= '1';
      ticks(300);
      tap_restore;
      ticks(500);
      assert keys(75) = '0' and keys(67) = '1' and events = 1
         report "CTRL + RESTORE was stolen by the menu" severity failure;
      pressed <= (others => '0');
      ticks(750);

      ------------------------------------------------------------------
      -- PB8 does not alias either extension position into a RESTORE event.
      ------------------------------------------------------------------
      extra_pb8 <= '1';
      ticks(300);
      assert keys(67) = '1' and keys(75) = '1' and events = 1
         report "PB8 produced a RESTORE event" severity failure;
      extra_pb8 <= '0';
      ticks(300);

      ------------------------------------------------------------------
      -- Reset while pressed clears the synthetic state; a low input held
      -- across reset cannot create a phantom new event.
      ------------------------------------------------------------------
      pressed(C_CELL_MEGA) <= '1';
      ticks(300);
      restore_n <= '0';
      ticks(100);
      assert events = 2 severity failure;
      rst <= '1';
      ticks(10);
      assert keys(67) = '1' and keys(75) = '1'
         report "Reset did not release the stretched press" severity failure;
      rst <= '0';
      ticks(1500);
      assert events = 2 report "Phantom press after reset" severity failure;
      restore_n <= '1';
      ticks(220);
      tap_restore;
      ticks(1250);
      assert events = 3 report "Did not rearm after reset" severity failure;
      pressed <= (others => '0');
      ticks(300);

      ------------------------------------------------------------------
      -- QNICE navigation: RUN/STOP stays local, the top-left arrow is the
      -- menu's back/cancel key (bit 6).
      ------------------------------------------------------------------
      pressed(C_CELL_RUN_STOP) <= '1'; ticks(300);
      assert qkeys = x"FFFF" report "RUN/STOP leaked into menu navigation"
         severity failure;
      pressed(C_CELL_RUN_STOP) <= '0'; pressed(C_CELL_ESC) <= '1'; ticks(300);
      assert qkeys = x"FFBF" report "Top-left Escape not routed to QNICE"
         severity failure;

      report "PASS: bare RESTORE to the NMI, C= chord to the menu, " &
             "RUN/STOP and CTRL not qualifiers, bounce, hold, rearm, " &
             "modifier order, OSM gating and Escape";
      finish;
   end process;

   watchdog : process
   begin
      wait for 1 ms;
      assert false report "RESTORE test timed out" severity failure;
   end process;
end architecture;
