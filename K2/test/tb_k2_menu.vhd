-- Read the real configuration ROM port and guard the QNICE menu heap budget.
--
-- This replaces AExp-K2's tb_k2_menu, which asserted Amiga menu rows, labels
-- and an eight-page help set.  The valuable part is kept and retargeted: the
-- menu is read through work.config's actual ROM interface (not the generator's
-- text files), and the exact heap demand that M2M/rom/options.asm computes at
-- runtime is recomputed here, so growth fails in simulation instead of as a
-- FATAL on hardware.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library std;
use std.env.all;

entity tb_k2_menu is
   generic (
      -- From CORE/vhdl/globals.vhd: C_VDNUM and C_CRTROMS_MAN_NUM.
      G_VDRIVES        : natural := 1;
      G_CRTROM_MAN     : natural := 2;
      -- From CORE/vhdl/config.vhd: OPTM_SIZE, OPTM_DX.
      G_OPTM_SIZE      : natural := 98;
      G_OPTM_DX        : natural := 25;
      -- From CORE/m2m-rom/m2m-rom.asm.
      G_MENU_HEAP_SIZE : natural := 1664;
      -- Welcome page plus HELP_1..HELP_3, and the geometry those pages use.
      G_PAGES          : natural := 4;
      G_HELP_COLUMNS   : natural := 43;
      G_HELP_ROWS      : natural := 30
   );
end entity;

architecture test of tb_k2_menu is
   signal clk     : std_logic := '0';
   signal address : std_logic_vector(27 downto 0) := (others => '0');
   signal data    : std_logic_vector(15 downto 0);
begin
   clk <= not clk after 5 ns;
   dut : entity work.config
      port map (clk_i => clk, address_i => address, data_o => data);

   stimulus : process
      variable text        : string(1 to 8192);
      variable size, row, first, max_label : natural := 0;
      variable submenu_rows, submenus      : natural := 0;
      variable heap1, optm_heap, demand    : natural;
      variable lines, line_width, max_width : natural;

      function contains(haystack, needle : string) return boolean is
      begin
         if needle'length > haystack'length then return false; end if;
         for i in haystack'low to haystack'high - needle'length + 1 loop
            if haystack(i to i + needle'length - 1) = needle then return true; end if;
         end loop;
         return false;
      end function;

      procedure read_word(sel : natural; index : natural) is
      begin
         address <= std_logic_vector(to_unsigned(sel + index, 28));
         wait until falling_edge(clk);
         wait for 1 ns;
      end procedure;
   begin
      ---------------------------------------------------------------------
      -- OPTM_ITEMS: row count, label width and the K2 headline.
      ---------------------------------------------------------------------
      for i in 0 to 8190 loop
         read_word(16#0300000#, i);
         exit when unsigned(data) = 0;
         text(i + 1) := character'val(to_integer(unsigned(data)));
         size := i + 1;
      end loop;

      first := 1;
      for i in 2 to size loop
         if text(i - 1 to i) = "\n" then
            if i - 1 - first > max_label then max_label := i - 1 - first; end if;
            row   := row + 1;
            first := i + 1;
         end if;
      end loop;

      assert row = G_OPTM_SIZE
         report "Menu item count " & natural'image(row) & " /= OPTM_SIZE"
         severity failure;
      assert max_label <= G_OPTM_DX
         report "Menu label exceeds OPTM_DX: " & natural'image(max_label)
         severity failure;
      assert contains(text(1 to size), " C64 for K2\n")  -- literal backslash-n, as stored
         report "K2 menu headline missing" severity failure;
      assert not contains(text(1 to size), "for MEGA65")
         report "Menu still names the MEGA65" severity failure;

      ---------------------------------------------------------------------
      -- Submenu count, exactly as _HLP_S4 in M2M/rom/options.asm does it:
      -- OPTM_G_SUBMENU is 16#0C000#, and the ROM port exposes bits 15 and 14.
      -- Every submenu contributes a start and an end marker, so the raw count
      -- must be even; the firmware FATALs (ERR_F_MENUSUB) otherwise.
      ---------------------------------------------------------------------
      for i in 0 to G_OPTM_SIZE - 1 loop
         read_word(16#0301000#, i);
         if data(15) = '1' and data(14) = '1' then
            submenu_rows := submenu_rows + 1;
         end if;
      end loop;
      assert submenu_rows mod 2 = 0
         report "Odd number of OPTM_G_SUBMENU markers" severity failure;
      submenus := submenu_rows / 2;

      ---------------------------------------------------------------------
      -- The two live budgets from HELP_MENU in M2M/rom/options.asm.
      -- LOG_HEAP1: menu struct + item string + terminator + three OPTM_SIZE
      -- arrays + 1.  LOG_HEAP2: one SCR$OSM_O_DX-wide (OPTM_DX + 2) buffer per
      -- virtual drive, submenu and manual ROM, plus one scratch buffer.
      ---------------------------------------------------------------------
      heap1     := 19 + size + 1 + 3 * G_OPTM_SIZE + 1;
      optm_heap := (G_VDRIVES + submenus + G_CRTROM_MAN + 1) * (G_OPTM_DX + 2);
      demand    := heap1 + optm_heap;

      assert demand <= G_MENU_HEAP_SIZE
         report "Menu heap overflow: demand " & natural'image(demand) &
                " > MENU_HEAP_SIZE " & natural'image(G_MENU_HEAP_SIZE)
         severity failure;

      report "PASS: menu rows=" & natural'image(row) &
             " itemstring=" & natural'image(size) &
             " maxlabel=" & natural'image(max_label) &
             " submenus=" & natural'image(submenus) &
             " heap1=" & natural'image(heap1) &
             " optm_heap=" & natural'image(optm_heap) &
             " demand=" & natural'image(demand) &
             " headroom=" & natural'image(G_MENU_HEAP_SIZE - demand);

      ---------------------------------------------------------------------
      -- Welcome and help pages, through the ROM port rather than the files.
      ---------------------------------------------------------------------
      for page in 0 to G_PAGES - 1 loop
         size := 0; line_width := 0; lines := 0; max_width := 0;
         for i in 0 to 8190 loop
            if page = 0 then
               read_word(16#1000000#, i);
            else
               read_word(16#1100000#, (page - 1) * 4096 + i);
            end if;
            exit when unsigned(data) = 0;
            text(i + 1) := character'val(to_integer(unsigned(data)));
            size := i + 1;
            line_width := line_width + 1;
            if i > 0 and text(i to i + 1) = "\n" then
               if line_width - 2 > max_width then max_width := line_width - 2; end if;
               line_width := 0;
               lines := lines + 1;
            end if;
         end loop;

         assert size > 100 and size < 8190
            report "Help page " & natural'image(page) & " has an implausible size"
            severity failure;
         assert max_width <= G_HELP_COLUMNS
            report "Help page " & natural'image(page) & " line too wide: " &
                   natural'image(max_width)
            severity failure;
         assert lines <= G_HELP_ROWS and line_width = 0
            report "Help page " & natural'image(page) & " exceeds geometry"
            severity failure;
         assert not contains(text(1 to size), "for MEGA65")
            report "Help page " & natural'image(page) & " still names the MEGA65"
            severity failure;

         -- Controls and limitations that are specific to this board, so a
         -- careless help-page edit cannot quietly restore MEGA65 wording.
         if page = 0 then
            assert contains(text(1 to size), "hold C= and")
               report "Welcome page does not name the K2 menu chord" severity failure;
            assert contains(text(1 to size), "RUN/STOP + RESTORE")
               report "Welcome page does not preserve the C64 warm reset"
               severity failure;
            assert contains(text(1 to size), "HDMI only")
               report "Welcome page does not state HDMI-only output" severity failure;
         elsif page = 1 then
            assert contains(text(1 to size), "no expansion port")
               report "About page does not state the missing cartridge port"
               severity failure;
            assert contains(text(1 to size), "c64k2")
               report "About page does not name the K2 settings file" severity failure;
         elsif page = 2 then
            assert contains(text(1 to size), "C= + RESTORE:")
               report "Keyboard page does not bind C= + RESTORE to the menu"
               severity failure;
            assert not contains(text(1 to size), "Help:")
               report "Keyboard page still binds the MEGA65 Help key" severity failure;
            -- The chord exists so these two C64 behaviours survive; if the
            -- page stops saying so, the binding has probably been changed.
            assert contains(text(1 to size), "C64 NMI")
               report "Keyboard page no longer documents the bare RESTORE NMI"
               severity failure;
            assert contains(text(1 to size), "RUN/STOP +")
               report "Keyboard page no longer documents the warm reset"
               severity failure;
         elsif page = 3 then
            assert contains(text(1 to size), "no analog VGA")
               report "Status page does not state the missing VGA output"
               severity failure;
            assert contains(text(1 to size), "STAT_LED0")
               report "Status page does not describe the board LEDs" severity failure;
         end if;
      end loop;

      report "PASS: all " & natural'image(G_PAGES) &
             " K2 welcome/help pages, geometry and board-specific controls";
      finish;
   end process;
end architecture;
