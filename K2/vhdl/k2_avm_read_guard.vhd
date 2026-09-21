-- Preserve the upstream arbiter's non-pipelined read contract in front of
-- a command FIFO. A new command must not replace a pending read's accounting.
--
-- Note the failure mode this creates: there is no timeout, so if the memory
-- path ever loses a read word, "remaining" never reaches zero and the whole
-- Avalon side locks up instead of glitching. That is deliberate -- it matches
-- the blocking HyperRAM controller the framework was written for, and a silent
-- glitch is what made the original fault so hard to find. The response FIFO in
-- framework_k2 must stay deep enough for the largest burst in the design
-- (crt_cacher's 128 words); see K2/README.md.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity k2_avm_read_guard is
   port (
      clk_i, rst_i : in std_logic;
      s_read_i, s_write_i : in std_logic;
      s_burstcount_i : in std_logic_vector(7 downto 0);
      s_waitrequest_o : out std_logic;
      m_read_o, m_write_o : out std_logic;
      m_waitrequest_i, readdatavalid_i : in std_logic
   );
end entity;

architecture rtl of k2_avm_read_guard is
   signal remaining : unsigned(7 downto 0) := (others => '0');
   signal blocked : std_logic;
begin
   blocked <= '1' when rst_i = '1' or remaining /= 0 else '0';
   s_waitrequest_o <= blocked or m_waitrequest_i;
   m_read_o <= s_read_i and not blocked;
   m_write_o <= s_write_i and not blocked;
   process(clk_i)
   begin
      if rising_edge(clk_i) then
         if rst_i = '1' then
            remaining <= (others => '0');
         elsif s_read_i = '1' and s_waitrequest_o = '0' then
            remaining <= unsigned(s_burstcount_i);
            -- synthesis translate_off
            assert unsigned(s_burstcount_i) /= 0
               report "Read guard received a zero-length burst" severity failure;
            -- synthesis translate_on
         elsif readdatavalid_i = '1' and remaining /= 0 then
            remaining <= remaining - 1;
         end if;
      end if;
   end process;
end architecture;
