-- Passive QNICE-side image mount measurement. Counts accepted byte writes,
-- wait cycles and SD activity, never changes the loading or drive protocol.
-- Published bundle is stable between millisecond snapshots for cdc_stable.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity k2_load_monitor is
   generic (G_PUBLISH_CYCLES : positive := 50000;
            -- QNICE device whose byte writes are measured; C64 default is the
            -- disk-image buffer (C_DEV_C64_MOUNT).
            C_MONITOR_DEV    : std_logic_vector(15 downto 0) := x"0102");
   port (
      clk_i, reset_i : in std_logic;
      dev_i : in std_logic_vector(15 downto 0);
      addr_i : in std_logic_vector(27 downto 0);
      data_i, data_o_i : in std_logic_vector(15 downto 0);
      ce_i, we_i, wait_i : in std_logic;
      sd_cs_n_i, sd_clk_i : in std_logic;
      stats_o : out std_logic_vector(319 downto 0) := (others => '0')
   );
end entity;

architecture rtl of k2_load_monitor is
   signal sequence_no, elapsed, bytes, waits, sd_active, first_byte, last_byte,
          sd_edges : unsigned(31 downto 0) := (others => '0');
   signal crc : unsigned(31 downto 0) := (others => '1');
   signal flags : std_logic_vector(31 downto 0) := (others => '0');
   signal seen, old_sd_clk : std_logic := '0';
   signal publish_count : natural range 0 to G_PUBLISH_CYCLES-1 := 0;
   signal publish_pending : boolean := false;
   function crc_byte(c : unsigned(31 downto 0); b : std_logic_vector(7 downto 0)) return unsigned is
      variable v : unsigned(31 downto 0) := c xor resize(unsigned(b),32);
   begin
      for i in 0 to 7 loop
         if v(0) = '1' then v := (v srl 1) xor x"EDB88320";
         else v := v srl 1; end if;
      end loop;
      return v;
   end function;
begin
   -- QNICE MMIO writes commit on the falling edge. The SD outputs are also
   -- generated from QNICE-derived clocks; sampled activity is diagnostic only.
   process(clk_i)
      variable access_now : boolean;
   begin
      if falling_edge(clk_i) then
         old_sd_clk <= sd_clk_i;
         access_now := ce_i = '1' and wait_i = '0' and seen = '0' and dev_i = C_MONITOR_DEV;
         if ce_i = '0' then seen <= '0';
         elsif wait_i = '0' then seen <= '1'; end if;
         if flags(0) = '1' then
            elapsed <= elapsed+1;
            if ce_i = '1' and we_i = '1' and wait_i = '1' and dev_i = C_MONITOR_DEV then waits <= waits+1; end if;
            if sd_cs_n_i = '0' then
               sd_active <= sd_active+1;
               if sd_clk_i = '1' and old_sd_clk = '0' then sd_edges <= sd_edges+1; end if;
            end if;
            if access_now and we_i = '1' and unsigned(addr_i(27 downto 12)) < x"FFFE" then
               if bytes = 0 then first_byte <= elapsed; end if;
               last_byte <= elapsed; bytes <= bytes+1;
               crc <= crc_byte(crc,data_i(7 downto 0));
            end if;
            if access_now and ((we_i = '0' and addr_i = x"FFFF010" and
               (data_o_i(3 downto 0) = x"2" or data_o_i(3 downto 0) = x"3")) or
               (we_i = '1' and addr_i = x"FFFF000" and data_i(3 downto 0) = x"2")) then
               flags(0) <= '0'; flags(1) <= '1';
               if we_i = '1' or data_o_i(3 downto 0) = x"3" then flags(2) <= '1'; end if;
               publish_pending <= true;
            end if;
         end if;
         if access_now and we_i = '1' and addr_i = x"FFFF000" and data_i(3 downto 0) = x"1" then
            sequence_no <= sequence_no+1; flags <= x"00000001";
            elapsed <= (others => '0'); bytes <= (others => '0'); waits <= (others => '0');
            sd_active <= (others => '0'); first_byte <= (others => '0'); last_byte <= (others => '0');
            sd_edges <= (others => '0'); crc <= (others => '1'); publish_pending <= true;
         end if;
         if publish_count = G_PUBLISH_CYCLES-1 or publish_pending then
            -- Little-endian u32 fields in wire order, low word first.
            stats_o <= std_logic_vector(sd_edges) & std_logic_vector(not crc) &
                       std_logic_vector(last_byte) & std_logic_vector(first_byte) &
                       std_logic_vector(sd_active) & std_logic_vector(waits) &
                       std_logic_vector(bytes) & std_logic_vector(elapsed) & flags & std_logic_vector(sequence_no);
            publish_count <= 0; publish_pending <= false;
         else publish_count <= publish_count+1; end if;
         if reset_i = '1' then
            sequence_no <= (others => '0'); flags <= (others => '0');
            elapsed <= (others => '0'); bytes <= (others => '0'); waits <= (others => '0');
            sd_active <= (others => '0'); first_byte <= (others => '0'); last_byte <= (others => '0');
            sd_edges <= (others => '0'); crc <= (others => '1'); seen <= '0';
            publish_count <= 0; publish_pending <= false; stats_o <= (others => '0');
         end if;
      end if;
   end process;
end architecture;
