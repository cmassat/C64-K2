----------------------------------------------------------------------------------
-- Self-checking test for the K2 DDR3 application path.
--
-- Exercises an unaligned 16-bit Avalon burst, independently stalled MIG command
-- and write-data channels, byte enables, and the reverse 128-to-16-bit read path.
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.env.all;

entity tb_avm_mig_path is
end entity tb_avm_mig_path;

architecture test of tb_avm_mig_path is

   constant C_CLK_PERIOD : time := 12 ns;

   signal clk        : std_logic := '0';
   signal rst        : std_logic := '1';
   signal calib_done : std_logic := '0';

   signal s_write         : std_logic := '0';
   signal s_read          : std_logic := '0';
   signal s_address       : std_logic_vector(31 downto 0) := (others => '0');
   signal s_writedata     : std_logic_vector(15 downto 0) := (others => '0');
   signal s_byteenable    : std_logic_vector(1 downto 0) := (others => '0');
   signal s_burstcount    : std_logic_vector(7 downto 0) := (others => '0');
   signal s_readdata      : std_logic_vector(15 downto 0);
   signal s_readdatavalid : std_logic;
   signal s_waitrequest   : std_logic;

   signal w_write         : std_logic;
   signal w_read          : std_logic;
   signal w_address       : std_logic_vector(28 downto 0);
   signal w_writedata     : std_logic_vector(127 downto 0);
   signal w_byteenable    : std_logic_vector(15 downto 0);
   signal w_burstcount    : std_logic_vector(7 downto 0);
   signal w_readdata      : std_logic_vector(127 downto 0);
   signal w_readdatavalid : std_logic;
   signal w_waitrequest   : std_logic;
   signal w_readcredit    : std_logic;

   signal app_addr          : std_logic_vector(26 downto 0);
   signal app_cmd           : std_logic_vector(2 downto 0);
   signal app_en            : std_logic;
   signal app_rdy           : std_logic := '0';
   signal app_wdf_data      : std_logic_vector(63 downto 0);
   signal app_wdf_end       : std_logic;
   signal app_wdf_mask      : std_logic_vector(7 downto 0);
   signal app_wdf_wren      : std_logic;
   signal app_wdf_rdy       : std_logic := '0';
   signal app_rd_data       : std_logic_vector(63 downto 0) := (others => '0');
   signal app_rd_data_valid : std_logic := '0';
   signal app_rd_data_end   : std_logic := '0';

   type t_memory is array (0 to 127) of std_logic_vector(127 downto 0);
   signal memory : t_memory := (others => (others => '0'));

begin

   clk <= not clk after C_CLK_PERIOD / 2;

   i_width : entity work.k2_avm_increase
      port map (
         clk_i                 => clk,
         rst_i                 => rst,
         s_avm_write_i         => s_write,
         s_avm_read_i          => s_read,
         s_avm_address_i       => s_address,
         s_avm_writedata_i     => s_writedata,
         s_avm_byteenable_i    => s_byteenable,
         s_avm_burstcount_i    => s_burstcount,
         s_avm_readdata_o      => s_readdata,
         s_avm_readdatavalid_o => s_readdatavalid,
         s_avm_waitrequest_o   => s_waitrequest,
         m_avm_write_o         => w_write,
         m_avm_read_o          => w_read,
         m_avm_address_o       => w_address,
         m_avm_writedata_o     => w_writedata,
         m_avm_byteenable_o    => w_byteenable,
         m_avm_burstcount_o    => w_burstcount,
         m_avm_readdata_i      => w_readdata,
         m_avm_readdatavalid_i => w_readdatavalid,
         m_avm_waitrequest_i   => w_waitrequest,
         m_avm_readcredit_o    => w_readcredit
      );

   i_bridge : entity work.avm_mig_bridge
      generic map (
         -- Deliberately remove the production issue gap here.  Together
         -- with the long-latency MIG model below this fills every reserved
         -- response slot and exercises credit-based throttling directly.
         G_READ_GAP_CYCLES => 0,
         G_READ_CREDITS    => 7
      )
      port map (
         clk_i                 => clk,
         rst_i                 => rst,
         calib_done_i          => calib_done,
         s_avm_write_i         => w_write,
         s_avm_read_i          => w_read,
         s_avm_address_i       => w_address,
         s_avm_writedata_i     => w_writedata,
         s_avm_byteenable_i    => w_byteenable,
         s_avm_burstcount_i    => w_burstcount,
         s_avm_readdata_o      => w_readdata,
         s_avm_readdatavalid_o => w_readdatavalid,
         s_avm_waitrequest_o   => w_waitrequest,
         s_avm_readcredit_i    => w_readcredit,
         app_addr_o            => app_addr,
         app_cmd_o             => app_cmd,
         app_en_o              => app_en,
         app_rdy_i             => app_rdy,
         app_wdf_data_o        => app_wdf_data,
         app_wdf_end_o         => app_wdf_end,
         app_wdf_mask_o        => app_wdf_mask,
         app_wdf_wren_o        => app_wdf_wren,
         app_wdf_rdy_i         => app_wdf_rdy,
         app_rd_data_i         => app_rd_data,
         app_rd_data_valid_i   => app_rd_data_valid,
         app_rd_data_end_i     => app_rd_data_end
      );

   -- A small behavioral MIG application-port model.  The command and write
   -- data channels stall on unrelated schedules and may therefore handshake
   -- in either order.
   p_mig : process (clk)
      type t_read_queue is array (0 to 31) of natural range memory'range;
      variable cycle_count     : natural := 0;
      variable write_addr      : natural range memory'range := 0;
      variable write_addr_seen : boolean := false;
      variable write_data      : std_logic_vector(127 downto 0) := (others => '0');
      variable write_mask      : std_logic_vector(15 downto 0) := (others => '1');
      variable write_low_seen  : boolean := false;
      variable write_data_seen : boolean := false;
      variable read_queue      : t_read_queue := (others => 0);
      variable read_head       : natural range read_queue'range := 0;
      variable read_tail       : natural range read_queue'range := 0;
      variable read_count      : natural range 0 to read_queue'length := 0;
      variable read_holdoff    : natural range 0 to 50 := 0;
      variable read_high_half  : boolean := false;
   begin
      if rising_edge(clk) then
         cycle_count := cycle_count + 1;
         app_rdy     <= '0' when cycle_count mod 3 = 0 else '1';
         app_wdf_rdy <= '0' when cycle_count mod 4 < 2 else '1';

         app_rd_data_valid <= '0';
         app_rd_data_end   <= '0';

         -- Hold the first response long enough for all seven bridge credits
         -- to be reserved, then return complete DDR words on consecutive
         -- pairs of clocks.  This is intentionally more bursty than MIG.
         if read_high_half then
            app_rd_data_valid <= '1';
            app_rd_data       <= memory(read_queue(read_head))(127 downto 64);
            app_rd_data_end   <= '1';
            read_high_half    := false;
            read_head         := (read_head + 1) mod read_queue'length;
            read_count        := read_count - 1;
         elsif read_count > 0 and read_holdoff = 0 then
            app_rd_data_valid <= '1';
            app_rd_data       <= memory(read_queue(read_head))(63 downto 0);
            app_rd_data_end   <= '0';
            read_high_half    := true;
         elsif read_holdoff > 0 then
            read_holdoff := read_holdoff - 1;
         end if;

         if app_en = '1' and app_rdy = '1' then
            assert app_addr(26 downto 10) = (app_addr(26 downto 10)'range => '0')
               report "test accessed memory outside the behavioral MIG model"
               severity failure;
            if app_cmd = "000" then
               assert not write_addr_seen
                  report "two MIG write commands are outstanding"
                  severity failure;
               write_addr      := to_integer(unsigned(app_addr(9 downto 3)));
               write_addr_seen := true;
            elsif app_cmd = "001" then
               assert read_count < read_queue'length
                  report "behavioral MIG read queue overflow"
                  severity failure;
               read_queue(read_tail) := to_integer(unsigned(app_addr(9 downto 3)));
               read_tail             := (read_tail + 1) mod read_queue'length;
               if read_count = 0 and not read_high_half then
                  read_holdoff := 50;
               end if;
               read_count := read_count + 1;
            else
               assert false report "unexpected MIG command" severity failure;
            end if;
         end if;

         if app_wdf_wren = '1' and app_wdf_rdy = '1' then
            if app_wdf_end = '0' then
               assert not write_low_seen and not write_data_seen
                  report "unexpected first MIG write-data beat" severity failure;
               write_data(63 downto 0) := app_wdf_data;
               write_mask(7 downto 0)  := app_wdf_mask;
               write_low_seen          := true;
            else
               assert write_low_seen and not write_data_seen
                  report "unexpected terminal MIG write-data beat" severity failure;
               write_data(127 downto 64) := app_wdf_data;
               write_mask(15 downto 8)   := app_wdf_mask;
               write_low_seen            := false;
               write_data_seen           := true;
            end if;
         end if;

         if write_addr_seen and write_data_seen then
            for byte_index in 0 to 15 loop
               if write_mask(byte_index) = '0' then
                  memory(write_addr)(8*byte_index+7 downto 8*byte_index) <=
                     write_data(8*byte_index+7 downto 8*byte_index);
               end if;
            end loop;
            write_addr_seen := false;
            write_data_seen := false;
         end if;

         if rst = '1' then
            cycle_count     := 0;
            write_addr_seen := false;
            write_low_seen  := false;
            write_data_seen := false;
            read_head       := 0;
            read_tail       := 0;
            read_count      := 0;
            read_holdoff    := 0;
            read_high_half  := false;
            app_rdy         <= '0';
            app_wdf_rdy     <= '0';
         end if;
      end if;
   end process;

   p_test : process
      procedure p_write_burst(
         constant address     : in natural;
         constant word_count  : in positive;
         constant first_value : in natural
      ) is
      begin
         s_address    <= std_logic_vector(to_unsigned(address, s_address'length));
         s_burstcount <= std_logic_vector(to_unsigned(word_count, s_burstcount'length));
         s_byteenable <= "11";
         s_write      <= '1';

         for word_index in 0 to word_count-1 loop
            s_writedata <= std_logic_vector(to_unsigned(first_value + word_index, 16));
            loop
               wait until rising_edge(clk);
               exit when s_waitrequest = '0';
            end loop;
         end loop;

         s_write <= '0';
         wait until rising_edge(clk);
      end procedure;

      procedure p_read_and_check(
         constant address     : in natural;
         constant word_count  : in positive;
         constant first_value : in natural
      ) is
         variable expected : std_logic_vector(15 downto 0);
      begin
         s_address    <= std_logic_vector(to_unsigned(address, s_address'length));
         s_burstcount <= std_logic_vector(to_unsigned(word_count, s_burstcount'length));
         s_read       <= '1';
         loop
            wait until rising_edge(clk);
            exit when s_waitrequest = '0';
         end loop;
         s_read <= '0';

         for word_index in 0 to word_count-1 loop
            loop
               wait until rising_edge(clk);
               exit when s_readdatavalid = '1';
            end loop;
            expected := std_logic_vector(to_unsigned(first_value + word_index, 16));
            if address + word_index = 4 then
               expected(7 downto 0) := x"55";
            end if;
            assert s_readdata = expected
               report "read mismatch at 16-bit word address " &
                      integer'image(address + word_index) & ": got 0x" &
                      to_hstring(s_readdata) & ", expected 0x" & to_hstring(expected)
               severity failure;
         end loop;
      end procedure;
   begin
      wait for 6 * C_CLK_PERIOD;
      wait until rising_edge(clk);
      rst        <= '0';
      calib_done <= '1';
      wait until rising_edge(clk);

      -- 13 words starting at lane 3 exercise both a partial and a full
      -- 128-bit native DDR beat.
      p_write_burst(3, 13, 16#1000#);

      -- Change only the low byte at word address 4.
      s_address    <= std_logic_vector(to_unsigned(4, s_address'length));
      s_burstcount <= x"01";
      s_writedata  <= x"AA55";
      s_byteenable <= "01";
      s_write      <= '1';
      loop
         wait until rising_edge(clk);
         exit when s_waitrequest = '0';
      end loop;
      s_write <= '0';
      -- The bridge acknowledges once the write is safely buffered; MIG
      -- command/data completion is intentionally decoupled from Avalon.
      for settle_cycle in 0 to 11 loop
         wait until rising_edge(clk);
      end loop;

      assert memory(0)(16*3+15 downto 16*3) = x"1000"
         report "first native DDR write was not committed" severity failure;
      assert memory(1)(15 downto 0) = x"1005"
         report "second native DDR write was not committed" severity failure;

      p_read_and_check(3, 13, 16#1000#);

      -- Eight wide words require the bridge to stop at seven outstanding
      -- reads until the width adapter returns its first FIFO credit.
      p_write_burst(16, 64, 16#2000#);
      p_read_and_check(16, 64, 16#2000#);

      report "PASS: K2 Avalon-to-MIG path" severity note;
      stop;
      wait;
   end process;

   p_watchdog : process
   begin
      wait for 20 us;
      assert false report "K2 Avalon-to-MIG test timed out" severity failure;
      wait;
   end process;

end architecture test;
