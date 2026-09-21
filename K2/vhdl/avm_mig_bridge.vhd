----------------------------------------------------------------------------------
-- AExp for Wildbits K2 RevB0C
--
-- Translate a 128-bit Avalon-MM stream into the native 7-series MIG
-- application interface used by the K2's 128 MiB DDR3.  The K2 MIG uses a
-- 2:1 PHY ratio and therefore exposes 64 application data bits: every fixed
-- BL8 command transfers two application beats, combined here into one Avalon
-- word.
--
-- Address contract:
--   * Avalon addresses are 128-bit-word based.
--   * MIG app_addr is the same address with three low zero bits, matching the
--     K2 reference DDR3 design and its fixed BL8 native interface.
--
-- Read commands are pipelined, but issued no more often than once per eight
-- UI-clock cycles.  The upstream width adapter consumes one 128-bit response
-- over eight 16-bit Avalon cycles; explicit response-buffer credits make this
-- safe even if DDR latency bunches several returns together.  This sustains
-- the adapter's full rate while keeping its queue in LUTRAM rather than
-- precious block RAM.  Command issue is independent of return latency.
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity avm_mig_bridge is
   generic (
      G_AVM_ADDRESS_SIZE : positive := 29;
      G_READ_GAP_CYCLES  : natural  := 7;
      G_READ_CREDITS     : positive := 7
   );
   port (
      clk_i                 : in  std_logic;
      rst_i                 : in  std_logic;
      calib_done_i          : in  std_logic;

      s_avm_write_i         : in  std_logic;
      s_avm_read_i          : in  std_logic;
      s_avm_address_i       : in  std_logic_vector(G_AVM_ADDRESS_SIZE-1 downto 0);
      s_avm_writedata_i     : in  std_logic_vector(127 downto 0);
      s_avm_byteenable_i    : in  std_logic_vector(15 downto 0);
      s_avm_burstcount_i    : in  std_logic_vector(7 downto 0);
      s_avm_readdata_o      : out std_logic_vector(127 downto 0);
      s_avm_readdatavalid_o : out std_logic;
      s_avm_waitrequest_o   : out std_logic;
      s_avm_readcredit_i    : in  std_logic;

      app_addr_o            : out std_logic_vector(26 downto 0);
      app_cmd_o             : out std_logic_vector(2 downto 0);
      app_en_o              : out std_logic;
      app_rdy_i             : in  std_logic;
      app_wdf_data_o        : out std_logic_vector(63 downto 0);
      app_wdf_end_o         : out std_logic;
      app_wdf_mask_o        : out std_logic_vector(7 downto 0);
      app_wdf_wren_o        : out std_logic;
      app_wdf_rdy_i         : in  std_logic;
      app_rd_data_i         : in  std_logic_vector(63 downto 0);
      app_rd_data_valid_i   : in  std_logic;
      app_rd_data_end_i     : in  std_logic
   );
end entity avm_mig_bridge;

architecture rtl of avm_mig_bridge is

   type t_state is (IDLE_ST, WRITE_ISSUE_ST, WRITE_CAPTURE_ST,
                    READ_ACTIVE_ST);
   signal state : t_state := IDLE_ST;

   signal address_reg       : unsigned(G_AVM_ADDRESS_SIZE-1 downto 0) := (others => '0');
   signal remaining_reg     : unsigned(7 downto 0) := (others => '0');
   signal write_data_reg    : std_logic_vector(127 downto 0) := (others => '0');
   signal write_be_reg      : std_logic_vector(15 downto 0) := (others => '0');
   signal write_cmd_sent    : std_logic := '0';
   signal write_data_sent   : std_logic := '0';
   signal write_data_half   : std_logic := '0';
   signal read_cmd_left     : unsigned(7 downto 0) := (others => '0');
   signal read_rsp_left     : unsigned(7 downto 0) := (others => '0');
   signal read_low_reg      : std_logic_vector(63 downto 0) := (others => '0');
   signal read_low_seen     : std_logic := '0';
   signal read_data_reg     : std_logic_vector(127 downto 0) := (others => '0');
   signal read_valid_reg    : std_logic := '0';
   signal read_gap_count    : natural range 0 to G_READ_GAP_CYCLES := 0;
   signal read_credit_count : natural range 0 to G_READ_CREDITS := G_READ_CREDITS;

   signal write_cmd_now     : std_logic;
   signal write_data_now    : std_logic;
   signal write_accept_now  : std_logic;
   signal read_cmd_accept   : std_logic;

   function f_nonzero_burst(value : std_logic_vector(7 downto 0)) return unsigned is
   begin
      if unsigned(value) = 0 then
         return to_unsigned(1, 8);
      end if;
      return unsigned(value);
   end function;

begin

   assert G_AVM_ADDRESS_SIZE >= 24
      report "avm_mig_bridge needs at least 24 wide-word address bits"
      severity failure;

   -- The K2 MIG reference connects a 24-bit 128-bit-word address to app_addr
   -- with three low zeros.  AExp currently uses only the first few MiB.
   app_addr_o <= std_logic_vector(address_reg(23 downto 0)) & "000";

   app_cmd_o      <= "000" when state = WRITE_ISSUE_ST else "001";
   app_en_o       <= '1' when state = READ_ACTIVE_ST and
                              read_cmd_left /= 0 and read_gap_count = 0 and
                              read_credit_count /= 0 else
                     '1' when state = WRITE_ISSUE_ST and write_cmd_sent = '0' else
                     '0';
   app_wdf_data_o <= write_data_reg(63 downto 0) when write_data_half = '0' else
                     write_data_reg(127 downto 64);
   app_wdf_mask_o <= not write_be_reg(7 downto 0) when write_data_half = '0' else
                     not write_be_reg(15 downto 8);
   app_wdf_end_o  <= write_data_half;
   app_wdf_wren_o <= '1' when state = WRITE_ISSUE_ST and write_data_sent = '0' else '0';

   write_cmd_now    <= write_cmd_sent or app_rdy_i;
   write_data_now   <= write_data_sent or (app_wdf_rdy_i and write_data_half);
   write_accept_now <= write_cmd_now and write_data_now when state = WRITE_ISSUE_ST else '0';
   read_cmd_accept  <= '1' when state = READ_ACTIVE_ST and
                               app_en_o = '1' and app_rdy_i = '1' else
                       '0';

   -- Accept the Avalon request into local registers.  MIG readiness is then
   -- handled wholly inside this bridge, avoiding a long combinatorial path
   -- from app_rdy through the M2M arbiter and its clients.
   s_avm_waitrequest_o <= '0' when state = IDLE_ST and calib_done_i = '1' and
                                   (s_avm_write_i = '1' or s_avm_read_i = '1') else
                          '0' when state = WRITE_CAPTURE_ST and s_avm_write_i = '1' else
                          '1';

   s_avm_readdata_o      <= read_data_reg;
   s_avm_readdatavalid_o <= read_valid_reg;

   p_fsm : process (clk_i)
   begin
      if rising_edge(clk_i) then
         read_valid_reg <= '0';

         case state is
            when IDLE_ST =>
               if calib_done_i = '1' and s_avm_write_i = '1' then
                  address_reg     <= unsigned(s_avm_address_i);
                  remaining_reg   <= f_nonzero_burst(s_avm_burstcount_i);
                  write_data_reg  <= s_avm_writedata_i;
                  write_be_reg    <= s_avm_byteenable_i;
                  write_cmd_sent  <= '0';
                  write_data_sent <= '0';
                  write_data_half <= '0';
                  state           <= WRITE_ISSUE_ST;
               elsif calib_done_i = '1' and s_avm_read_i = '1' then
                  address_reg    <= unsigned(s_avm_address_i);
                  read_cmd_left  <= f_nonzero_burst(s_avm_burstcount_i);
                  read_rsp_left  <= f_nonzero_burst(s_avm_burstcount_i);
                  read_gap_count <= 0;
                  read_low_seen  <= '0';
                  state          <= READ_ACTIVE_ST;
               end if;

            when WRITE_ISSUE_ST =>
               if app_rdy_i = '1' then
                  write_cmd_sent <= '1';
               end if;
               if app_wdf_rdy_i = '1' and write_data_sent = '0' then
                  if write_data_half = '0' then
                     write_data_half <= '1';
                  else
                     write_data_sent <= '1';
                  end if;
               end if;

               if write_accept_now = '1' then
                  write_cmd_sent  <= '0';
                  write_data_sent <= '0';
                  write_data_half <= '0';
                  if remaining_reg = 1 then
                     remaining_reg <= (others => '0');
                     state         <= IDLE_ST;
                  else
                     remaining_reg <= remaining_reg - 1;
                     address_reg   <= address_reg + 1;
                     state         <= WRITE_CAPTURE_ST;
                  end if;
               end if;

            when WRITE_CAPTURE_ST =>
               -- Avalon holds the next burst beat while waitrequest is high.
               if s_avm_write_i = '1' then
                  write_data_reg  <= s_avm_writedata_i;
                  write_be_reg    <= s_avm_byteenable_i;
                  write_cmd_sent  <= '0';
                  write_data_sent <= '0';
                  write_data_half <= '0';
                  state           <= WRITE_ISSUE_ST;
               end if;

            when READ_ACTIVE_ST =>
               -- The MIG accepts multiple native read commands.  Space them
               -- by eight clocks so their 128-bit responses cannot outrun the
               -- 16-bit side of k2_avm_increase, but do not pay DDR latency
               -- again between commands in a burst.
               if read_gap_count /= 0 then
                  read_gap_count <= read_gap_count - 1;
               end if;

               if app_en_o = '1' and app_rdy_i = '1' then
                  read_cmd_left  <= read_cmd_left - 1;
                  address_reg    <= address_reg + 1;
                  read_gap_count <= G_READ_GAP_CYCLES;
               end if;

               if app_rd_data_valid_i = '1' then
                  if read_low_seen = '0' then
                     assert app_rd_data_end_i = '0'
                        report "K2 MIG ended a BL8 read after its first 64-bit beat"
                        severity failure;
                     read_low_reg  <= app_rd_data_i;
                     read_low_seen <= '1';
                  else
                     assert app_rd_data_end_i = '1'
                        report "K2 MIG did not end a BL8 read on its second 64-bit beat"
                        severity failure;
                     read_data_reg  <= app_rd_data_i & read_low_reg;
                     read_valid_reg <= '1';
                     read_low_seen  <= '0';

                     if read_rsp_left = 1 then
                        assert read_cmd_left = 0 or
                               (read_cmd_left = 1 and app_en_o = '1' and app_rdy_i = '1')
                           report "K2 MIG returned more reads than were issued"
                           severity failure;
                        read_rsp_left <= (others => '0');
                        state         <= IDLE_ST;
                     else
                        read_rsp_left <= read_rsp_left - 1;
                     end if;
                  end if;
               end if;
         end case;

         -- Reserve one FIFO slot for every accepted MIG read command and
         -- return it only when the width adapter consumes the complete
         -- 128-bit response.  Simultaneous issue/consume leaves the count
         -- unchanged.
         if read_cmd_accept = '1' and s_avm_readcredit_i = '0' then
            assert read_credit_count > 0
               report "K2 DDR read-response credit underflow"
               severity failure;
            read_credit_count <= read_credit_count - 1;
         elsif read_cmd_accept = '0' and s_avm_readcredit_i = '1' then
            assert read_credit_count < G_READ_CREDITS
               report "K2 DDR read-response credit overflow"
               severity failure;
            read_credit_count <= read_credit_count + 1;
         end if;

         if rst_i = '1' or calib_done_i = '0' then
            state             <= IDLE_ST;
            remaining_reg     <= (others => '0');
            write_cmd_sent    <= '0';
            write_data_sent   <= '0';
            write_data_half   <= '0';
            read_cmd_left     <= (others => '0');
            read_rsp_left     <= (others => '0');
            read_low_seen     <= '0';
            read_valid_reg    <= '0';
            read_gap_count    <= 0;
            read_credit_count <= G_READ_CREDITS;
         end if;
      end if;
   end process;

end architecture rtl;
