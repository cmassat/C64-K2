----------------------------------------------------------------------------------
-- AExp for Wildbits K2 RevB0C
--
-- Width adapter from the M2M 16-bit, word-addressed Avalon interface to the
-- 128-bit interface used by the K2 DDR3 MIG application port.
--
-- This is intentionally K2-local.  It is derived from M2M's avm_increase.vhd,
-- but its read FIFO is deliberately shallow: the downstream MIG bridge
-- throttles read responses to no more than one 128-bit word per eight clocks.
-- Keeping the FIFO at eight entries makes Vivado infer LUTRAM instead of
-- consuming the final AExp BRAM tile.
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.numeric_std_unsigned.all;

entity k2_avm_increase is
   generic (
      G_SLAVE_ADDRESS_SIZE  : integer := 32;
      G_SLAVE_DATA_SIZE     : integer := 16;
      G_MASTER_ADDRESS_SIZE : integer := 29;
      G_MASTER_DATA_SIZE    : integer := 128;
      G_READ_FIFO_DEPTH     : integer := 8
   );
   port (
      clk_i                 : in  std_logic;
      rst_i                 : in  std_logic;

      s_avm_write_i         : in  std_logic;
      s_avm_read_i          : in  std_logic;
      s_avm_address_i       : in  std_logic_vector(G_SLAVE_ADDRESS_SIZE-1 downto 0);
      s_avm_writedata_i     : in  std_logic_vector(G_SLAVE_DATA_SIZE-1 downto 0);
      s_avm_byteenable_i    : in  std_logic_vector(G_SLAVE_DATA_SIZE/8-1 downto 0);
      s_avm_burstcount_i    : in  std_logic_vector(7 downto 0);
      s_avm_readdata_o      : out std_logic_vector(G_SLAVE_DATA_SIZE-1 downto 0);
      s_avm_readdatavalid_o : out std_logic;
      s_avm_waitrequest_o   : out std_logic;

      m_avm_write_o         : out std_logic;
      m_avm_read_o          : out std_logic;
      m_avm_address_o       : out std_logic_vector(G_MASTER_ADDRESS_SIZE-1 downto 0);
      m_avm_writedata_o     : out std_logic_vector(G_MASTER_DATA_SIZE-1 downto 0);
      m_avm_byteenable_o    : out std_logic_vector(G_MASTER_DATA_SIZE/8-1 downto 0);
      m_avm_burstcount_o    : out std_logic_vector(7 downto 0);
      m_avm_readdata_i      : in  std_logic_vector(G_MASTER_DATA_SIZE-1 downto 0);
      m_avm_readdatavalid_i : in  std_logic;
      m_avm_waitrequest_i   : in  std_logic;
      -- One pulse when a complete wide read response leaves the FIFO.  The
      -- MIG bridge uses this to return a reserved response-buffer credit.
      m_avm_readcredit_o    : out std_logic
   );
end entity k2_avm_increase;

architecture synthesis of k2_avm_increase is

   constant C_RATIO         : integer := G_MASTER_DATA_SIZE / G_SLAVE_DATA_SIZE;
   constant C_ADDRESS_SHIFT : integer := G_SLAVE_ADDRESS_SIZE - G_MASTER_ADDRESS_SIZE;

   type t_state is (IDLE_ST, WRITING_ST, READING_ST, RESPONSE_ST);
   signal state : t_state := IDLE_ST;

   signal offset              : std_logic_vector(C_ADDRESS_SHIFT-1 downto 0) := (others => '0');
   signal s_burstcount        : std_logic_vector(7 downto 0) := (others => '0');
   signal m_avm_readdata      : std_logic_vector(G_MASTER_DATA_SIZE-1 downto 0);
   signal m_avm_readdatavalid : std_logic;
   signal m_avm_ready         : std_logic;
   signal read_fifo_ready     : std_logic;

begin

   assert C_RATIO > 1 severity failure;
   assert C_ADDRESS_SHIFT > 0 severity failure;
   assert G_MASTER_DATA_SIZE = C_RATIO * G_SLAVE_DATA_SIZE severity failure;
   -- Compare the width ratio, rather than total address-space sizes.  The
   -- latter overflows a 32-bit VHDL integer for the 32-bit M2M address bus.
   assert C_RATIO = 2**C_ADDRESS_SHIFT
      severity failure;

   s_avm_waitrequest_o <= '0' when (state = IDLE_ST or state = WRITING_ST) and
                                  (m_avm_write_o = '0' or m_avm_waitrequest_i = '0') else
                          '1';

   p_fsm : process (clk_i)
      pure function f_master_burstcount(
         address    : std_logic_vector;
         burstcount : std_logic_vector
      ) return std_logic_vector is
         variable res : std_logic_vector(G_SLAVE_ADDRESS_SIZE+1 downto 0);
      begin
         res := (("00" & address) + burstcount - 1) / C_RATIO -
                (("00" & address) / C_RATIO) + 1;
         return res(7 downto 0);
      end function;
   begin
      if rising_edge(clk_i) then
         if m_avm_waitrequest_i = '0' then
            m_avm_read_o  <= '0';
            m_avm_write_o <= '0';
            if m_avm_write_o = '1' then
               m_avm_byteenable_o <= (others => '0');
            end if;
         end if;

         case state is
            when IDLE_ST =>
               if s_avm_write_i = '1' and s_avm_waitrequest_o = '0' then
                  m_avm_write_o      <= '1';
                  m_avm_read_o       <= '0';
                  m_avm_address_o    <= s_avm_address_i(G_SLAVE_ADDRESS_SIZE-1 downto C_ADDRESS_SHIFT);
                  m_avm_byteenable_o <= (others => '0');
                  m_avm_burstcount_o <= f_master_burstcount(s_avm_address_i, s_avm_burstcount_i);

                  for i in 0 to C_RATIO-1 loop
                     if i = to_integer(s_avm_address_i(C_ADDRESS_SHIFT-1 downto 0)) then
                        m_avm_writedata_o(G_SLAVE_DATA_SIZE*(i+1)-1 downto G_SLAVE_DATA_SIZE*i) <=
                           s_avm_writedata_i;
                        m_avm_byteenable_o(G_SLAVE_DATA_SIZE/8*(i+1)-1 downto G_SLAVE_DATA_SIZE/8*i) <=
                           s_avm_byteenable_i;
                     end if;
                  end loop;

                  if s_avm_burstcount_i /= x"01" then
                     m_avm_write_o <= '0';
                     s_burstcount  <= s_avm_burstcount_i - 1;
                     offset        <= s_avm_address_i(C_ADDRESS_SHIFT-1 downto 0) + 1;
                     state         <= WRITING_ST;
                  end if;

                  if and(s_avm_address_i(C_ADDRESS_SHIFT-1 downto 0)) then
                     m_avm_write_o <= '1';
                  end if;
               end if;

               if s_avm_read_i = '1' and s_avm_waitrequest_o = '0' then
                  m_avm_write_o      <= '0';
                  m_avm_read_o       <= '1';
                  m_avm_address_o    <= s_avm_address_i(G_SLAVE_ADDRESS_SIZE-1 downto C_ADDRESS_SHIFT);
                  m_avm_burstcount_o <= f_master_burstcount(s_avm_address_i, s_avm_burstcount_i);
                  s_burstcount       <= s_avm_burstcount_i;
                  offset             <= s_avm_address_i(C_ADDRESS_SHIFT-1 downto 0);
                  state              <= READING_ST;
               end if;

            when WRITING_ST =>
               if s_avm_write_i = '1' and s_avm_waitrequest_o = '0' and s_burstcount > 0 then
                  s_burstcount <= s_burstcount - 1;
                  offset       <= offset + 1;

                  if offset = C_RATIO-1 then
                     m_avm_write_o <= '1';
                  end if;

                  for i in 0 to C_RATIO-1 loop
                     if i = to_integer(offset) then
                        m_avm_writedata_o(G_SLAVE_DATA_SIZE*(i+1)-1 downto G_SLAVE_DATA_SIZE*i) <=
                           s_avm_writedata_i;
                        m_avm_byteenable_o(G_SLAVE_DATA_SIZE/8*(i+1)-1 downto G_SLAVE_DATA_SIZE/8*i) <=
                           s_avm_byteenable_i;
                     end if;
                  end loop;

                  if s_burstcount = 1 then
                     m_avm_write_o <= '1';
                     state         <= IDLE_ST;
                  end if;
               end if;

            when READING_ST =>
               if m_avm_readdatavalid = '1' then
                  s_burstcount <= s_burstcount - 1;
                  offset       <= offset + 1;
                  if s_burstcount > 1 then
                     state <= RESPONSE_ST;
                  else
                     state <= IDLE_ST;
                  end if;
               end if;

            when RESPONSE_ST =>
               -- The original M2M adapter assumes the next wide word is
               -- already queued by the time offset wraps.  DDR3 read latency
               -- can leave a legal gap between native responses, so advance
               -- the narrow response only while the FIFO actually has data.
               if m_avm_readdatavalid = '1' then
                  if s_burstcount > 1 then
                     s_burstcount <= s_burstcount - 1;
                     offset       <= offset + 1;
                  else
                     state <= IDLE_ST;
                  end if;
               end if;
         end case;

         if rst_i = '1' then
            m_avm_read_o       <= '0';
            m_avm_write_o      <= '0';
            m_avm_byteenable_o <= (others => '0');
            state              <= IDLE_ST;
         end if;
      end if;
   end process;

   s_avm_readdata_o <=
      m_avm_readdata(G_SLAVE_DATA_SIZE*(to_integer(offset)+1)-1 downto
                     G_SLAVE_DATA_SIZE*to_integer(offset));

   s_avm_readdatavalid_o <= m_avm_readdatavalid when state = READING_ST else
                            m_avm_readdatavalid when state = RESPONSE_ST else
                            '0';

   m_avm_ready <= '1' when offset = C_RATIO-1 or state = IDLE_ST else '0';
   m_avm_readcredit_o <= m_avm_ready and m_avm_readdatavalid;

   -- Each downstream response has a credit reserved before its MIG command
   -- is issued, so loss here is always a design error rather than legal
   -- Avalon backpressure.
   assert not (m_avm_readdatavalid_i = '1' and read_fifo_ready = '0')
      report "K2 DDR read-response FIFO overflow"
      severity failure;

   i_read_fifo : entity work.axi_fifo_small
      generic map (
         G_RAM_WIDTH => G_MASTER_DATA_SIZE,
         G_RAM_DEPTH => G_READ_FIFO_DEPTH
      )
      port map (
         clk_i     => clk_i,
         rst_i     => rst_i,
         s_ready_o => read_fifo_ready,
         s_valid_i => m_avm_readdatavalid_i,
         s_data_i  => m_avm_readdata_i,
         m_ready_i => m_avm_ready,
         m_valid_o => m_avm_readdatavalid,
         m_data_o  => m_avm_readdata
      );

end architecture synthesis;
