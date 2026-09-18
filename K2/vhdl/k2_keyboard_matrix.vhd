----------------------------------------------------------------------------------
-- Wildbits K2 optical keyboard scanner (mechanical keyboards unsupported).
--
-- Release the selected PA row, ground the other seven; PB is HIGH for a hit.
-- This is the physical-pin behaviour of the reference OpticalKeyboardScanner
-- through IO_Page0_Devices/IO_BiDir8 (RowDrive is an output-enable mask, NOT
-- the value driven on PA). Grounding every row disables the IR LEDs.
--
-- Most cells retain C64 numbering. K2's four independent cursors do not:
-- PA0/PB2=Left, PA0/PB7=Up, PA0/PB8=Down, PA6/PB8=Right. Source: local
-- FoenixToolbox/src/dev/kbd_f256k.c and F256_MicroKernel/f256/kbd_f256k2.asm.
-- RESTORE's active-low pulse becomes a 100 ms Help (67) press, auto-released.
-- Sample halfway into each 1 ms row, beyond the reference 50 us IR settling
-- interval; two scans debounce both make and break (at most 16 ms).
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity k2_keyboard_matrix is
   generic (
      G_CLK_SPEED : positive := 100_000_000;
      G_ROW_HZ    : positive := 1000
   );
   port (
      clk_i             : in    std_logic;
      rst_i             : in    std_logic;
      restore_n_i       : in    std_logic := '1';
      pa_io             : inout std_logic_vector(7 downto 0);
      pb_io             : inout std_logic_vector(8 downto 0);
      key_state_n_o     : out   std_logic_vector(79 downto 0)
   );
end entity k2_keyboard_matrix;

architecture rtl of k2_keyboard_matrix is

   constant C_ROW_TICKS    : positive := G_CLK_SPEED / G_ROW_HZ;
   constant C_SAMPLE_TICK  : natural  := C_ROW_TICKS / 2;
   constant C_RESTORE_TICKS : positive := G_CLK_SPEED / 10; -- 100 ms press
   constant C_REARM_TICKS   : positive := G_CLK_SPEED / 50; -- 20 ms quiet high

   type t_debounce is array (0 to 71) of natural range 0 to 2;
   signal debounce_count : t_debounce := (others => 0);
   signal matrix_n       : std_logic_vector(71 downto 0) := (others => '1');
   signal pb_meta        : std_logic_vector(8 downto 0) := (others => '0');
   signal pb_sync        : std_logic_vector(8 downto 0) := (others => '0');
   signal pa_drive       : std_logic_vector(7 downto 0) := (others => '0');
   signal row_index      : natural range 0 to 7 := 0;
   signal row_count      : natural range 0 to C_ROW_TICKS-1 := 0;
   signal restore_meta_n : std_logic := '1';
   signal restore_sync_n : std_logic := '1';
   signal restore_armed  : std_logic := '0';
   signal restore_reset  : std_logic := '0';
   signal restore_count  : natural range 0 to C_RESTORE_TICKS := 0;
   signal rearm_count    : natural range 0 to C_REARM_TICKS := 0;

   attribute ASYNC_REG : string;
   attribute ASYNC_REG of restore_meta_n, restore_sync_n : signal is "TRUE";
   attribute ASYNC_REG of pb_meta, pb_sync : signal is "TRUE";

begin

   pa_io <= pa_drive;
   pb_io <= (others => 'Z');

   -- RESTORE is separate from the matrix and need not report key-up. Stretch
   -- its synchronized assertion for the main/QNICE CDC and firmware polling.
   -- Ignore bounce during the fixed press, then require a quiet high interval
   -- before accepting another assertion. A held-low input cannot auto-repeat;
   -- reset also requires an idle interval before the first event.
   p_restore : process (clk_i)
   begin
      if rising_edge(clk_i) then
         restore_meta_n <= restore_n_i;
         restore_sync_n <= restore_meta_n;

         if rst_i = '1' then
            restore_armed <= '0';
            restore_reset <= '0';
            restore_count <= 0;
            rearm_count   <= 0;
         elsif restore_count > 0 then
            restore_count <= restore_count - 1;
            rearm_count   <= 0;
         elsif restore_sync_n = '1' then
            if rearm_count < C_REARM_TICKS then
               rearm_count <= rearm_count + 1;
            end if;
            if rearm_count = C_REARM_TICKS - 1 then
               restore_armed <= '1';
            end if;
         else
            rearm_count <= 0;
            if restore_armed = '1' and restore_sync_n = '0' then
               restore_count <= C_RESTORE_TICKS;
               restore_armed <= '0';
               -- Qualify once, before either destination sees the pulse.
               -- Physical CTRL=PA7/PB2, /F=PA7/PB5. Fn is irrelevant.
               restore_reset <= not (matrix_n(7*9+2) or matrix_n(7*9+5));
            end if;
         end if;
      end if;
   end process;

   -- Explicit sensitivity includes the index used on the assignment target.
   p_row_drive : process (row_index, rst_i)
   begin
      pa_drive <= (others => '0');
      if rst_i = '0' then
         pa_drive(row_index) <= 'Z';
      end if;
   end process;

   p_scan : process (clk_i)
      variable cell : natural range 0 to 71;
   begin
      if rising_edge(clk_i) then
         pb_meta <= pb_io;
         pb_sync <= pb_meta;

         if row_count = C_SAMPLE_TICK then
            for column in 0 to 8 loop
               cell := row_index * 9 + column;
               if column = 8 and row_index /= 0 and row_index /= 6 then
                  -- No optical switch on these extension cells.
                  debounce_count(cell) <= 0;
                  matrix_n(cell) <= '1';
               elsif pb_sync(column) = '1' then
                  if debounce_count(cell) < 2 then
                     debounce_count(cell) <= debounce_count(cell) + 1;
                  end if;
                  if debounce_count(cell) >= 1 then
                     matrix_n(cell) <= '0';
                  end if;
               else
                  if debounce_count(cell) > 0 then
                     debounce_count(cell) <= debounce_count(cell) - 1;
                  end if;
                  if debounce_count(cell) <= 1 then
                     matrix_n(cell) <= '1';
                  end if;
               end if;
            end loop;
         end if;

         if row_count = C_ROW_TICKS-1 then
            row_count <= 0;
            if row_index = 7 then
               row_index <= 0;
            else
               row_index <= row_index + 1;
            end if;
         else
            row_count <= row_count + 1;
         end if;

         if rst_i = '1' then
            row_index      <= 0;
            row_count      <= 0;
            debounce_count <= (others => 0);
            matrix_n       <= (others => '1');
            pb_meta        <= (others => '0');
            pb_sync        <= (others => '0');
         end if;
      end if;
   end process;

   p_map : process (all)
   begin
      key_state_n_o <= (others => '1');
      for row in 0 to 7 loop
         for column in 0 to 7 loop
            key_state_n_o(row*8 + column) <= matrix_n(row*9 + column);
         end loop;
      end loop;

      -- Override the two C64 cursor slots; all four K2 arrows are independent.
      key_state_n_o(74) <= matrix_n(2);       -- Left:  PA0/PB2
      key_state_n_o(73) <= matrix_n(7);       -- Up:    PA0/PB7
      key_state_n_o(7)  <= matrix_n(8);       -- Down:  PA0/PB8
      key_state_n_o(2)  <= matrix_n(6*9 + 8); -- Right: PA6/PB8

      -- Inherited AExp binding: RESTORE opens the OSM (slot 67).  Milestone M2
      -- moves RESTORE to slot 75 so it reaches the C64 NMI, and puts the menu on
      -- an Fn combo; C64MEGA65's keyboard.vhd defines m65_restore := 75.
      key_state_n_o(67) <= '0' when restore_count > 0 and restore_reset = '0' else '1';
      key_state_n_o(75) <= '0' when restore_count > 0 and restore_reset = '1' else '1';
   end process;

end architecture rtl;
