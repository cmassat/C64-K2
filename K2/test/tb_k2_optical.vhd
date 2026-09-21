-- Pin-level optical model: the released row illuminates, high PB means hit.
library ieee;
use ieee.std_logic_1164.all;
library std;
use std.env.all;

entity tb_k2_optical is
end entity;

architecture test of tb_k2_optical is
   constant C_ROW : time := 1 us; -- 100 cycles, accelerated 1 ms physical dwell
   constant C_SCAN : time := 8 * C_ROW;
   signal clk : std_logic := '0';
   signal main_clk : std_logic := '0';
   signal rst : std_logic := '1';
   signal pa : std_logic_vector(7 downto 0);
   signal pb : std_logic_vector(8 downto 0);
   signal pressed : std_logic_vector(71 downto 0) := (others => '0');
   signal keys : std_logic_vector(79 downto 0);
   signal qkeys : std_logic_vector(15 downto 0);
   signal core_enabled : std_logic := '1';
begin
   clk <= not clk after 5 ns;
   main_clk <= not main_clk after 7 ns;
   pa <= (others => 'H'); -- physical pull-ups, not actively driven highs

   dut : entity work.k2_keyboard_matrix
      generic map (G_CLK_SPEED => 100_000, G_ROW_HZ => 1000)
      port map (clk_i => clk, rst_i => rst, pa_io => pa, pb_io => pb,
                key_state_n_o => keys);
   adapter : entity work.k2_m2m_keyb
      port map (clk_main_i => main_clk, clk_main_speed_i => 100_000,
                key_state_n_i => keys, enable_core_i => core_enabled,
                key_num_o => open, key_pressed_n_o => open, qnice_keys_n_o => qkeys);

   no_phantom_menu : process (main_clk)
   begin
      if rising_edge(main_clk) and now > 100 ns then
         assert qkeys(7) = '1'
            report "Optical matrix transient generated a menu press" severity failure;
      end if;
   end process;

   optics : process (pa, pressed, rst)
      variable active_rows : natural;
      variable columns : std_logic_vector(8 downto 0);
   begin
      active_rows := 0;
      columns := (others => '0');
      for row in 0 to 7 loop
         if pa(row) = 'H' then
            active_rows := active_rows + 1;
            columns := columns or pressed(row*9 + 8 downto row*9);
         end if;
      end loop;
      -- Deliberately model a long settling transient on row changes. It must
      -- be ignored; both an inverted row mask and early sampling fail this TB.
      pb <= (others => '1'), columns after C_ROW / 5;
      if pa'event and now > 10 ns then
         if rst = '0' then
            assert active_rows = 1 report "Optical row-drive polarity wrong" severity failure;
         else
            assert active_rows = 0 report "IR LEDs active in reset" severity failure;
         end if;
      end if;
   end process;

   stimulus : process
      variable expected : std_logic_vector(79 downto 0);
      variable logical_key : natural;
      procedure settled is
      begin
         wait for 3 * C_SCAN;
      end procedure;
      procedure idle is
      begin
         pressed <= (others => '0');
         settled;
         assert keys = (keys'range => '1') report "Key failed to release" severity failure;
         assert qkeys = x"FFFF" report "QNICE still sees a held key" severity failure;
      end procedure;
   begin
      wait for 100 ns;
      rst <= '0';
      idle;

      -- All 66 populated cells, plus the six unpopulated PB8 positions.
      for cell in 0 to 71 loop
         pressed(cell) <= '1';
         settled;
         expected := (others => '1');
         if cell mod 9 /= 8 then
            logical_key := (cell / 9)*8 + cell mod 9;
            if cell = 2 then logical_key := 74; end if;
            if cell = 7 then logical_key := 73; end if;
            expected(logical_key) := '0';
         elsif cell = 8 then
            expected(7) := '0';
         elsif cell = 62 then
            expected(2) := '0';
         end if;
         assert keys = expected report "Wrong mapping at optical cell " &
            natural'image(cell) & ": actual=" & to_hstring(keys) &
            " expected=" & to_hstring(expected) severity failure;
         assert qkeys(7) = '1' report "Matrix key opened menu" severity failure;
         if cell = 2 then assert qkeys(3 downto 0) = "1011" severity failure; end if;
         if cell = 7 then assert qkeys(3 downto 0) = "1110" severity failure; end if;
         if cell = 8 then assert qkeys(3 downto 0) = "1101" severity failure; end if;
         if cell = 62 then assert qkeys(3 downto 0) = "0111" severity failure; end if;
         idle;
      end loop;

      -- Reproduce Down then Right in quick succession, including overlap and
      -- release with OSM/core-keyboard gating. Neither should be a menu key.
      pressed(8) <= '1';
      wait for C_ROW / 3;
      pressed(62) <= '1';
      core_enabled <= '0';
      settled;
      assert qkeys(7 downto 0) = "11110101"
         report "Down/Right overlap creates phantom key" severity failure;
      pressed(8) <= '0';
      settled;
      assert qkeys(7 downto 0) = "11110111"
         report "Down stuck after release" severity failure;
      idle;

      -- A disturbance shorter than a scan cannot pass the two-scan debounce.
      pressed(8) <= '1';
      wait for C_ROW;
      pressed(8) <= '0';
      settled;
      assert qkeys = x"FFFF" severity failure;
      pressed(7) <= '1';
      pressed(2) <= '1';
      settled;
      rst <= '1';
      wait for 100 ns;
      assert keys = (keys'range => '1') report "Reset did not clear keys" severity failure;
      pressed <= (others => '0');
      rst <= '0';
      idle;
      report "PASS: optical polarity, settling, 72 cells, four cursors, overlap, release, reset";
      finish;
   end process;

   watchdog : process
   begin
      wait for 10 ms;
      assert false report "Optical test timed out" severity failure;
   end process;
end architecture;
