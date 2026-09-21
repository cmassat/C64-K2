-- K2 PS/2 mouse host. Standard 3-byte reports, polled remote mode (~100 Hz).
-- Reset FF -> FA AA 00, defaults F6 -> FA, remote F0 -> FA, read EB -> FA+XYZ.
-- Protocol reference: ELAN EM84502 datasheet, pp.3-8 (PS/2 wire/remote mode).
-- Pins are open drain. Only complete parity/stop/header-checked packets commit.
-- A missing/bad reply releases buttons and retries initialization; no idle
-- streaming watchdog that could mistake an unmoving mouse for an unplug.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity k2_ps2_mouse is
   generic (G_CLK_HZ : positive := 28_437_500);
   port (
      clk_i, rst_i : in std_logic;
      ps2_clk_io, ps2_data_io : inout std_logic;
      dx_o, dy_o : out signed(9 downto 0);
      buttons_o : out std_logic_vector(2 downto 0); -- middle, right, left
      valid_o : out std_logic;
      ready_i : in std_logic;
      connected_o : out std_logic
   );
end entity;

architecture rtl of k2_ps2_mouse is
   function at_least_one(n : natural) return positive is
   begin
      if n = 0 then return 1; else return n; end if;
   end function;
   constant C_FILTER : positive := at_least_one(G_CLK_HZ / 1_000_000);
   constant C_INHIBIT : positive := at_least_one(G_CLK_HZ / 5000); -- 200 us
   constant C_SETUP : positive := at_least_one(G_CLK_HZ / 100_000); -- 10 us
   -- EM84502 permits 25 ms for command replies. Allow frame completion and
   -- clock tolerance too; the old 20 ms window rejected legal slow replies.
   constant C_REPLY : positive := at_least_one(G_CLK_HZ / 20); -- 50 ms
   constant C_BOOT : positive := at_least_one(G_CLK_HZ / 5); -- 200 ms retry
   constant C_POLL : positive := at_least_one(G_CLK_HZ / 100);
   signal clk_meta, clk_sync, dat_meta, dat_sync : std_logic := '1';
   signal clk_filtered, clk_previous : std_logic := '1';
   signal filter_count : natural range 0 to C_FILTER := 0;
   signal falling : std_logic;
   attribute ASYNC_REG : string;
   attribute ASYNC_REG of clk_meta, clk_sync, dat_meta, dat_sync : signal is "TRUE";

   type t_tx is (TX_IDLE, TX_INHIBIT, TX_SETUP, TX_BITS);
   signal tx_state : t_tx := TX_IDLE;
   signal tx_start, tx_done, tx_error : std_logic := '0';
   signal tx_data : std_logic_vector(7 downto 0) := x"FF";
   signal tx_frame : std_logic_vector(8 downto 0);
   signal tx_bit : natural range 0 to 10 := 0;
   signal tx_timer : natural range 0 to C_REPLY := 0;
   signal drive_clk, drive_data : std_logic := '0';
   signal rx_word : std_logic_vector(7 downto 0) := (others => '0');
   signal rx_parity : std_logic := '0';
   signal rx_bit : natural range 0 to 10 := 0;
   signal rx_timer : natural range 0 to C_REPLY := 0;
   signal rx_valid, rx_error : std_logic := '0';
   signal rx_data : std_logic_vector(7 downto 0) := (others => '0');
   signal link_reset : std_logic;

   type t_command is (RESET_MOUSE, DEFAULTS, REMOTE_MODE, READ_REPORT);
   type t_host is (BOOT_WAIT, SEND_COMMAND, WAIT_TX, WAIT_ACK, WAIT_BAT,
                  WAIT_ID, WAIT_STATUS, WAIT_X, WAIT_Y, REPORT_READY, POLL_WAIT);
   signal host_state : t_host := BOOT_WAIT;
   signal command : t_command := RESET_MOUSE;
   signal timer : natural range 0 to G_CLK_HZ := C_BOOT;
   signal poll_timer : natural range 0 to C_POLL := 0;
   signal status_byte, x_byte : std_logic_vector(7 downto 0) := (others => '0');
   signal valid : std_logic := '0';
begin
   ps2_clk_io <= '0' when drive_clk = '1' else 'Z';
   ps2_data_io <= '0' when drive_data = '1' else 'Z';
   falling <= clk_previous and not clk_filtered;
   valid_o <= valid;
   link_reset <= '1' when rst_i = '1' or host_state = BOOT_WAIT else '0';

   synchronize : process (clk_i)
   begin
      if rising_edge(clk_i) then
         clk_meta <= to_x01(ps2_clk_io); clk_sync <= clk_meta;
         dat_meta <= to_x01(ps2_data_io); dat_sync <= dat_meta;
         clk_previous <= clk_filtered;
         if clk_sync = clk_filtered then
            filter_count <= 0;
         elsif filter_count = C_FILTER - 1 then
            clk_filtered <= clk_sync;
            filter_count <= 0;
         else
            filter_count <= filter_count + 1;
         end if;
      end if;
   end process;

   wire_protocol : process (clk_i)
   begin
      if rising_edge(clk_i) then
         tx_done <= '0'; tx_error <= '0'; rx_valid <= '0'; rx_error <= '0';
         if tx_timer > 0 then tx_timer <= tx_timer - 1; end if;
         if rx_timer > 0 then rx_timer <= rx_timer - 1; end if;
         case tx_state is
            when TX_IDLE =>
               if tx_start = '1' then
                  tx_frame <= (not (xor tx_data)) & tx_data;
                  drive_clk <= '1'; drive_data <= '0';
                  tx_timer <= C_INHIBIT;
                  tx_state <= TX_INHIBIT;
                  rx_bit <= 0;
               end if;
            when TX_INHIBIT =>
               if tx_timer = 0 then
                  drive_data <= '1'; tx_timer <= C_SETUP; tx_state <= TX_SETUP;
               end if;
            when TX_SETUP =>
               if tx_timer = 0 then
                  drive_clk <= '0'; tx_bit <= 0;
                  tx_timer <= C_REPLY; tx_state <= TX_BITS;
               end if;
            when TX_BITS =>
               if tx_timer = 0 then
                  tx_error <= '1'; drive_data <= '0'; tx_state <= TX_IDLE;
               elsif falling = '1' then
                  if tx_bit < 9 then
                     drive_data <= not tx_frame(tx_bit);
                     tx_bit <= tx_bit + 1;
                  elsif tx_bit = 9 then
                     drive_data <= '0'; tx_bit <= 10; -- stop, then device ACK
                  else
                     if dat_sync = '0' then tx_done <= '1'; else tx_error <= '1'; end if;
                     tx_state <= TX_IDLE;
                  end if;
               end if;
         end case;

         if tx_state = TX_IDLE and tx_start = '0' then
            if rx_bit /= 0 and rx_timer = 0 then
               rx_bit <= 0; rx_error <= '1';
            elsif falling = '1' then
               rx_timer <= C_REPLY;
               case rx_bit is
                  when 0 =>
                     if dat_sync = '0' then rx_bit <= 1; else rx_error <= '1'; end if;
                  when 1 to 8 =>
                     rx_word(rx_bit-1) <= dat_sync; rx_bit <= rx_bit + 1;
                  when 9 => rx_parity <= dat_sync; rx_bit <= 10;
                  when 10 =>
                     rx_bit <= 0;
                     if dat_sync = '1' and ((xor rx_word) xor rx_parity) = '1' then
                        rx_data <= rx_word; rx_valid <= '1';
                     else rx_error <= '1'; end if;
               end case;
            end if;
         end if;
         if link_reset = '1' then
            tx_state <= TX_IDLE; drive_clk <= '0'; drive_data <= '0';
            rx_bit <= 0; tx_done <= '0'; tx_error <= '0'; rx_error <= '0'; rx_valid <= '0';
         end if;
      end if;
   end process;

   host : process (clk_i)
      variable fail : boolean;
   begin
      if rising_edge(clk_i) then
         fail := false;
         tx_start <= '0';
         if timer > 0 then timer <= timer - 1; end if;
         if poll_timer > 0 then poll_timer <= poll_timer - 1; end if;
         case host_state is
            when BOOT_WAIT =>
               if timer = 0 then command <= RESET_MOUSE; host_state <= SEND_COMMAND; end if;
            when SEND_COMMAND =>
               case command is
                  when RESET_MOUSE => tx_data <= x"FF";
                  when DEFAULTS => tx_data <= x"F6";
                  when REMOTE_MODE => tx_data <= x"F0";
                  when READ_REPORT => tx_data <= x"EB"; poll_timer <= C_POLL;
               end case;
               tx_start <= '1'; timer <= C_REPLY; host_state <= WAIT_TX;
            when WAIT_TX =>
               if tx_done = '1' then timer <= C_REPLY; host_state <= WAIT_ACK;
               elsif tx_error = '1' or timer = 0 then fail := true; end if;
            when WAIT_ACK =>
               if rx_valid = '1' then
                  if rx_data /= x"FA" then fail := true;
                  else
                     timer <= C_REPLY;
                     case command is
                        when RESET_MOUSE => timer <= G_CLK_HZ; host_state <= WAIT_BAT;
                        when DEFAULTS => command <= REMOTE_MODE; host_state <= SEND_COMMAND;
                        when REMOTE_MODE => connected_o <= '1'; host_state <= POLL_WAIT;
                        when READ_REPORT => host_state <= WAIT_STATUS;
                     end case;
                  end if;
               elsif timer = 0 then fail := true; end if;
            when WAIT_BAT =>
               if rx_valid = '1' then
                  if rx_data = x"AA" then timer <= C_REPLY; host_state <= WAIT_ID;
                  else fail := true; end if;
               elsif timer = 0 then fail := true; end if;
            when WAIT_ID =>
               if rx_valid = '1' then
                  if rx_data = x"00" then command <= DEFAULTS; host_state <= SEND_COMMAND;
                  else fail := true; end if;
               elsif timer = 0 then fail := true; end if;
            when WAIT_STATUS =>
               if rx_valid = '1' then
                  if rx_data(3) = '1' then
                     status_byte <= rx_data; timer <= C_REPLY; host_state <= WAIT_X;
                  else fail := true; end if;
               elsif timer = 0 then fail := true; end if;
            when WAIT_X =>
               if rx_valid = '1' then
                  x_byte <= rx_data; timer <= C_REPLY; host_state <= WAIT_Y;
               elsif timer = 0 then fail := true; end if;
            when WAIT_Y =>
               if rx_valid = '1' then
                  -- Drop an overflowing axis rather than inventing a wraparound
                  -- jump. Other-axis motion and button releases remain valid.
                  dx_o <= (others => '0'); dy_o <= (others => '0');
                  if status_byte(6) = '0' then dx_o <= resize(signed(status_byte(4) & x_byte), 10); end if;
                  if status_byte(7) = '0' then dy_o <= -resize(signed(status_byte(5) & rx_data), 10); end if;
                  buttons_o <= status_byte(2 downto 0);
                  valid <= '1'; host_state <= REPORT_READY;
               elsif timer = 0 then fail := true; end if;
            when REPORT_READY =>
               if ready_i = '1' then valid <= '0'; host_state <= POLL_WAIT; end if;
            when POLL_WAIT =>
               if poll_timer = 0 then command <= READ_REPORT; host_state <= SEND_COMMAND; end if;
         end case;
         if rx_error = '1' and host_state /= BOOT_WAIT then fail := true; end if;
         if rst_i = '1' or fail then
            host_state <= BOOT_WAIT; timer <= C_BOOT; poll_timer <= 0;
            tx_start <= '0'; valid <= '0'; connected_o <= '0';
            dx_o <= (others => '0'); dy_o <= (others => '0'); buttons_o <= "000";
         end if;
      end if;
   end process;
end architecture;
