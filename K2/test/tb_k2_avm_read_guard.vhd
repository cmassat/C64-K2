library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity tb_k2_avm_read_guard is end;
architecture test of tb_k2_avm_read_guard is
   signal clk : std_logic := '0';
   signal rst : std_logic := '1';
   signal sr, sw, mwait, rv : std_logic := '0';
   signal mr, mw, swait : std_logic;
   signal bc : std_logic_vector(7 downto 0) := x"01";
begin
   clk <= not clk after 5 ns;
   dut : entity work.k2_avm_read_guard port map (
      clk_i => clk, rst_i => rst, s_read_i => sr, s_write_i => sw,
      s_burstcount_i => bc, s_waitrequest_o => swait,
      m_read_o => mr, m_write_o => mw,
      m_waitrequest_i => mwait, readdatavalid_i => rv);
   process
      procedure tick is
      begin
         wait until rising_edge(clk); wait for 1 ns;
      end;
      procedure check_burst(n : positive) is
      begin
         bc <= std_logic_vector(to_unsigned(n, 8)); sr <= '1'; mwait <= '1';
         tick;
         assert swait = '1' and mr = '1' severity failure;
         mwait <= '0'; tick;
         assert swait = '1' and mr = '0' severity failure;
         sr <= '0'; sw <= '1';
         for i in 1 to n loop
            rv <= '0'; tick; tick;
            assert swait = '1' and mw = '0'
               report "Command leaked while read pending" severity failure;
            rv <= '1'; tick;
            rv <= '0';
            if i < n then
               assert swait = '1' and mw = '0' severity failure;
            else
               assert swait = '0' and mw = '1'
                  report "Guard did not release after final response" severity failure;
            end if;
         end loop;
         tick; sw <= '0'; tick;
      end;
   begin
      tick;
      assert swait = '1' and mr = '0' and mw = '0' severity failure;
      rst <= '0'; tick;
      check_burst(1);
      check_burst(64);
      check_burst(128);
      check_burst(255);
      sr <= '1'; bc <= x"40"; tick;
      sr <= '0'; rst <= '1'; tick;
      rst <= '0'; tick;
      assert swait = '0' report "Reset did not clear pending read" severity failure;
      check_burst(1);
      report "PASS: read guard burst lengths, response gaps, backpressure and reset";
      stop; wait;
   end process;
   process begin
      wait for 100 us;
      assert false report "Read guard timeout" severity failure;
   end process;
end;
