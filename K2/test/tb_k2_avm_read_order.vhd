-- Reproduce the arbitration contract when a command FIFO accepts requests
-- before an earlier read response has returned. No FPGA or MIG model needed.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_k2_avm_read_order is
   generic (G_SERIALIZE : boolean := false);
end entity;

architecture test of tb_k2_avm_read_order is
   signal clk : std_logic := '0';
   signal rst : std_logic := '1';
   signal rd0, wr0, wr1 : std_logic := '0';
   signal wait0, wait1, valid0, valid1 : std_logic;
   signal burst0 : std_logic_vector(7 downto 0) := x"04";
   signal mr, mw, wait_m : std_logic;
   signal mb : std_logic_vector(7 downto 0);
   signal rv : std_logic := '0';
   signal outstanding : natural range 0 to 255 := 0;
   signal got0, got1 : natural := 0;
begin
   clk <= not clk after 5 ns;
   gen_guard : if G_SERIALIZE generate
      guard : entity work.k2_avm_read_guard port map (
         clk_i => clk, rst_i => rst,
         s_read_i => mr, s_write_i => mw, s_burstcount_i => mb,
         s_waitrequest_o => wait_m, m_read_o => open, m_write_o => open,
         m_waitrequest_i => '0', readdatavalid_i => rv);
   end generate;
   unguarded : if not G_SERIALIZE generate
      wait_m <= '0';
   end generate;
   dut : entity work.avm_arbit
      generic map (G_PREFER_SWAP => true, G_ADDRESS_SIZE => 8, G_DATA_SIZE => 16)
      port map (
         clk_i => clk, rst_i => rst,
         s0_avm_write_i => wr0, s0_avm_read_i => rd0,
         s0_avm_address_i => x"00", s0_avm_writedata_i => x"0000",
         s0_avm_byteenable_i => "11", s0_avm_burstcount_i => burst0,
         s0_avm_readdata_o => open, s0_avm_readdatavalid_o => valid0,
         s0_avm_waitrequest_o => wait0,
         s1_avm_write_i => wr1, s1_avm_read_i => '0',
         s1_avm_address_i => x"10", s1_avm_writedata_i => x"1111",
         s1_avm_byteenable_i => "11", s1_avm_burstcount_i => x"01",
         s1_avm_readdata_o => open, s1_avm_readdatavalid_o => valid1,
         s1_avm_waitrequest_o => wait1,
         m_avm_write_o => mw, m_avm_read_o => mr,
         m_avm_address_o => open, m_avm_writedata_o => open,
         m_avm_byteenable_o => open, m_avm_burstcount_o => mb,
         m_avm_readdata_i => x"CAFE", m_avm_readdatavalid_i => rv,
         m_avm_waitrequest_i => wait_m);
   process(clk)
   begin
      if rising_edge(clk) then
         if mr = '1' and wait_m = '0' then
            outstanding <= to_integer(unsigned(mb));
         elsif rv = '1' and outstanding > 0 then
            outstanding <= outstanding - 1;
         end if;
         if valid0 = '1' then got0 <= got0 + 1; end if;
         if valid1 = '1' then got1 <= got1 + 1; end if;
         if rst = '1' then outstanding <= 0; got0 <= 0; got1 <= 0; end if;
      end if;
   end process;
   process
   begin
      wait for 100 ns;
      wait until falling_edge(clk); rst <= '0'; rd0 <= '1';
      loop wait until rising_edge(clk); exit when wait0 = '0'; end loop;
      wait until falling_edge(clk); rd0 <= '0';
      -- Same master issues a one-word write while its read is still pending.
      -- A FIFO accepts this; the original blocking memory interface does not.
      wr0 <= '1'; burst0 <= x"01";
      wait until rising_edge(clk);
      if not G_SERIALIZE then
         assert wait0 = '0' report "Expected FIFO-side acceptance" severity failure;
         wait until falling_edge(clk); wr0 <= '0';
      end if;
      -- A competing master waits to make premature grant changes observable.
      wr1 <= '1';
      wait for 80 ns;
      for i in 1 to 4 loop
         wait until falling_edge(clk); rv <= '1';
         wait until falling_edge(clk); rv <= '0';
      end loop;
      if G_SERIALIZE then
         loop wait until rising_edge(clk); exit when wait0 = '0'; end loop;
         wait until falling_edge(clk); wr0 <= '0';
      end if;
      wait for 100 ns;
      report "Read words routed to owner=" & integer'image(got0) &
             ", incorrectly to competitor=" & integer'image(got1);
      assert got0 = 4 and got1 = 0
         report "Read response ownership corrupted by accepting a later command" severity failure;
      report "PASS: all responses delivered to original owner";
      stop;
      wait;
   end process;
   process begin
      wait for 10 us;
      assert false report "Timeout: memory arbitration stalled" severity failure;
   end process;
end architecture;
