library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_k2_rtc is end;
architecture test of tb_k2_rtc is
   signal clk : std_logic := '0';
   signal rst : std_logic := '1';
   signal addr : std_logic_vector(3 downto 0);
   signal data : std_logic_vector(7 downto 0);
   signal cs, oe, owned, valid : std_logic;
   signal rtc, crossed : std_logic_vector(64 downto 0);
   signal dst_clk : std_logic := '0';
   type registers_t is array (0 to 15) of std_logic_vector(7 downto 0);
   signal regs : registers_t := (others => X"FF");
   signal change_during_sweep : boolean := false;
begin
   clk <= not clk after 5 ns;
   dst_clk <= not dst_clk after 17.6 ns;
   -- 1 ms represents one second; electrical read phases retain real timing.
   dut : entity work.k2_rtc
      generic map (G_SECOND_CYCLES => 100_000, G_POLL_CYCLES => 10_000,
                   G_START_CYCLES => 100, G_PHASE_CYCLES => 100)
      port map (clk, rst, data, addr, owned, cs, oe, rtc, valid);
   cdc : entity work.cdc_stable
      generic map (G_DATA_SIZE => 65, G_REGISTER_SRC => true)
      port map (clk, rtc, dst_clk, crossed);
   -- Real device worst-case delay (150 ns); release within 60 ns.
   data <= transport regs(to_integer(unsigned(addr))) after 150 ns
           when cs = '0' and oe = '0' else (others => 'Z') after 60 ns;

   process
      variable address_change, read_start, read_end : time := 0 ns;
   begin
      wait on addr, cs, rst;
      if addr'event then
         assert cs = '1' report "Address changed during read" severity failure;
         address_change := now;
      end if;
      if falling_edge(cs) then
         assert owned = '1' and rst = '0' report "RTC selected without bus ownership" severity failure;
         assert now-address_change >= 900 ns report "Address setup too short" severity failure;
         assert now-read_end >= 900 ns report "Bus recovery too short" severity failure;
         assert addr /= X"D" report "Read-to-clear flags register accessed" severity failure;
         read_start := now;
      elsif rising_edge(cs) and rst = '0' then
         assert now-read_start >= 1 us report "Read strobe too short" severity failure;
         read_end := now;
      end if;
   end process;

   process
      procedure load_time(s, m, h, d, dow, mo, y, c, control : std_logic_vector(7 downto 0)) is
      begin
         regs <= (0=>s, 2=>m, 4=>h, 6=>d, 8=>dow, 9=>mo, 10=>y, 15=>c, 14=>control, others=>X"FF");
      end;
      procedure expect(v : std_logic_vector(63 downto 0)) is
      begin
         wait until crossed(63 downto 0) = v for 500 us;
         assert crossed(63 downto 0) = v report "Expected RTC " & to_hstring(v) & " got " & to_hstring(crossed(63 downto 0)) severity failure;
      end;
      variable saved : std_logic_vector(63 downto 0);
   begin
      wait for 200 ns;
      assert cs = '1' and oe = '1' and owned = '0' severity failure;
      rst <= '0';
      wait for 65 ms; -- absent hardware: passes 59 -> 00 without freezing.
      assert crossed(15 downto 8) = X"01" report "Missing RTC fallback stuck before minute rollover" severity failure;
      assert valid = '0' severity failure;

      load_time(X"59",X"59",X"23",X"31",X"05",X"12",X"26",X"20",X"06");
      expect(X"4004261231235959");
      -- Identical hardware snapshots must not keep resetting seconds to 59.
      wait for 2100 us;
      assert crossed(55 downto 0) = X"05270101000001" report "Year/frozen-clock rollover failed" severity failure;

      load_time(X"59",X"59",X"23",X"28",X"04",X"02",X"24",X"20",X"06");
      expect(X"4003240228235959");
      wait for 1100 us;
      assert crossed(39 downto 24) = X"0229" report "Leap day failed" severity failure;
      load_time(X"59",X"59",X"23",X"28",X"01",X"02",X"00",X"21",X"06");
      expect(X"4000000228235959");
      wait for 1100 us;
      assert crossed(39 downto 24) = X"0301" report "2100 must not be leap year" severity failure;

      -- 12 AM -> 00, 12 PM -> 12, 1 PM -> 13; weekday 1..7 -> 0..6.
      load_time(X"12",X"34",X"12",X"11",X"06",X"09",X"26",X"20",X"04");
      expect(X"4005260911003412");
      load_time(X"13",X"34",X"92",X"11",X"06",X"09",X"26",X"20",X"04");
      expect(X"4005260911123413");
      load_time(X"14",X"34",X"81",X"11",X"06",X"09",X"26",X"20",X"04");
      expect(X"4005260911133414");

      -- Invalid BCD, dates, and UTI-frozen clock never discipline local time.
      regs(0) <= X"6A"; wait for 400 us;
      assert valid = '0' and crossed(23 downto 8) = X"1334" severity failure;
      load_time(X"00",X"00",X"00",X"31",X"01",X"02",X"26",X"20",X"06");
      wait for 400 us; assert valid = '0' severity failure;
      load_time(X"00",X"00",X"00",X"01",X"01",X"01",X"26",X"20",X"0E");
      wait for 400 us; assert valid = '0' severity failure;

      -- Deliberately change seconds between the two complete sweeps.
      load_time(X"20",X"40",X"10",X"12",X"07",X"09",X"26",X"20",X"06");
      wait until falling_edge(cs) and addr = X"0";
      wait until rising_edge(cs) and addr = X"E";
      regs(0) <= X"21";
      wait until rising_edge(cs) and addr = X"E";
      wait for 2 us;
      assert crossed(15 downto 8) /= X"40" report "Accepted torn snapshot" severity failure;
      expect(X"4006260912104021");

      -- Reset aborts an in-progress read and starts the ownership guard again.
      wait until falling_edge(cs); wait for 200 ns; rst <= '1'; wait for 50 ns;
      assert cs = '1' and oe = '1' and owned = '0' severity failure;
      rst <= '0'; expect(X"4006260912104021");
      report "PASS: RTC electrical timing, fallback, calendar, BCD, 12h/24h, coherence, CDC and reset" severity note;
      finish;
   end process;
   process begin wait for 100 ms; assert false report "RTC test timeout" severity failure; end process;
end;
