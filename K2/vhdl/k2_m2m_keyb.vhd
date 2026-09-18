----------------------------------------------------------------------------------
-- K2 bitmap-to-M2M keyboard adapter.
--
-- M2M cores consume one logical key number/status pair at a time.  The K2
-- board scanner instead produces the complete 80-key state, so this adapter
-- walks that bitmap and recreates the standard QNICE navigation-key vector.
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity k2_m2m_keyb is
   generic (
      SCAN_FREQUENCY : positive := 1000
   );
   port (
      clk_main_i       : in  std_logic;
      clk_main_speed_i : in  natural;
      key_state_n_i    : in  std_logic_vector(79 downto 0);
      enable_core_i    : in  std_logic;
      key_num_o        : out integer range 0 to 79;
      key_pressed_n_o  : out std_logic;
      osm_key_a_i      : in  integer range 0 to 79 := 67;
      osm_key_b_i      : in  integer range 0 to 79 := 67;
      osm_combo_i      : in  std_logic := '0';
      qnice_keys_n_o   : out std_logic_vector(15 downto 0)
   );
end entity k2_m2m_keyb;

architecture rtl of k2_m2m_keyb is

   signal key_state_meta_n : std_logic_vector(79 downto 0) := (others => '1');
   signal key_state_sync_n : std_logic_vector(79 downto 0) := (others => '1');
   signal key_snapshot_n   : std_logic_vector(79 downto 0) := (others => '1');
   signal core_snapshot_enabled : std_logic := '0';
   signal scan_slot        : integer range 0 to 79 := 0;
   signal key_num          : integer range 0 to 79 := 0;
   signal scan_count       : natural range 0 to 1_000_000 := 0;

   function f_ticks_per_key(
      clock_frequency : natural;
      scan_frequency  : positive
   ) return positive is
      variable result : natural;
   begin
      result := clock_frequency / scan_frequency / 80;
      if result = 0 then
         return 1;
      end if;
      return result;
   end function;

   type t_scan_order is array(0 to 79) of integer range 0 to 79;
   function f_scan_order return t_scan_order is
      variable order : t_scan_order := (others => 0);
      variable slot : natural := 6;
   begin
      -- Modifiers first, then all remaining keys once. A frozen bitmap per
      -- sweep means simultaneous Fn+1 cannot see 1 before the Fn state.
      order(0 to 5) := (63, 15, 52, 58, 61, 53);
      for key in 0 to 79 loop
         if key /= 63 and key /= 15 and key /= 52 and
            key /= 58 and key /= 61 and key /= 53 then
            order(slot) := key;
            slot := slot + 1;
         end if;
      end loop;
      return order;
   end function;
   constant C_SCAN_ORDER : t_scan_order := f_scan_order;

begin

   key_num         <= C_SCAN_ORDER(scan_slot);
   key_num_o       <= key_num;
   -- The already-qualified reset request also works while the OSM is open.
   key_pressed_n_o <= key_snapshot_n(key_num)
                     when (enable_core_i = '1' and core_snapshot_enabled = '1')
                          or key_num = 75 else '1';

   p_sync_and_scan : process (clk_main_i)
   begin
      if rising_edge(clk_main_i) then
         key_state_meta_n <= key_state_n_i;
         key_state_sync_n <= key_state_meta_n;

         if scan_count = f_ticks_per_key(clk_main_speed_i, SCAN_FREQUENCY)-1 then
            scan_count <= 0;
            if scan_slot = 79 then
               scan_slot <= 0;
               key_snapshot_n <= key_state_sync_n;
               core_snapshot_enabled <= enable_core_i;
            else
               scan_slot <= scan_slot + 1;
            end if;
         else
            scan_count <= scan_count + 1;
         end if;
      end if;
   end process;

   p_qnice_keys : process (all)
   begin
      qnice_keys_n_o    <= (others => '1');
      qnice_keys_n_o(0) <= key_state_sync_n(73); -- Cursor up
      qnice_keys_n_o(1) <= key_state_sync_n(7);  -- Cursor down
      qnice_keys_n_o(2) <= key_state_sync_n(74); -- Cursor left
      qnice_keys_n_o(3) <= key_state_sync_n(2);  -- Cursor right
      qnice_keys_n_o(4) <= key_state_sync_n(1);  -- Return
      qnice_keys_n_o(5) <= key_state_sync_n(60); -- Space
      qnice_keys_n_o(6) <= key_state_sync_n(57); -- top-left Escape; Fn stays local
      qnice_keys_n_o(8) <= key_state_sync_n(4);  -- F1
      qnice_keys_n_o(9) <= key_state_sync_n(5);  -- F3

      if osm_combo_i = '1' then
         qnice_keys_n_o(7) <= key_state_sync_n(osm_key_a_i) or
                              key_state_sync_n(osm_key_b_i);
         -- Preserve m2m_keyb's combo anti-bounce: while the first half is
         -- held, the second key is only the menu opener, not MENU UP.
         if key_state_sync_n(osm_key_a_i) = '0' then
            qnice_keys_n_o(6) <= '1';
         end if;
      else
         qnice_keys_n_o(7) <= key_state_sync_n(osm_key_a_i);
      end if;
   end process;

end architecture rtl;
