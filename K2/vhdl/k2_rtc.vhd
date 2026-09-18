-- K2 BQ4802LY read-only bridge, Matthias Brukner, 2026-09-11.
-- 100 MHz domain. No writes (including UTI/flags); two identical complete
-- sweeps plus BCD/calendar validation reject incoherent snapshots. Registers
-- change simultaneously per SLUS464C. No read of flags D (read-to-clear!).
-- A new hardware value disciplines a full local calendar. Repeated identical
-- values MUST NOT reseed it: a stopped/missing RTC must never freeze Amiga time.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity k2_rtc is
   generic (
      G_SECOND_CYCLES : positive := 100_000_000;
      G_POLL_CYCLES   : positive := 1_000_000;
      G_START_CYCLES  : positive := 100_000;
      G_PHASE_CYCLES  : positive := 100
   );
   port (
      clk_i, rst_i : in std_logic;
      data_i : in std_logic_vector(7 downto 0);
      address_o : out std_logic_vector(3 downto 0);
      bus_owned_o, cs_n_o, oe_n_o : out std_logic;
      rtc_o : out std_logic_vector(64 downto 0);
      hardware_valid_o : out std_logic
   );
end entity;

architecture rtl of k2_rtc is
   type bytes_t is array (0 to 8) of std_logic_vector(7 downto 0);
   type addresses_t is array (0 to 8) of natural range 0 to 15;
   constant C_ADDR : addresses_t := (0, 2, 4, 6, 8, 9, 10, 15, 14);
   type state_t is (startup, idle, setup_address, reading, recovery, check_snapshot);
   signal state : state_t := startup;
   signal phase : natural range 0 to G_PHASE_CYCLES-1 := 0;
   signal start_count : natural range 0 to G_START_CYCLES-1 := 0;
   signal poll_count : natural range 0 to G_POLL_CYCLES-1 := 0;
   signal second_count : natural range 0 to G_SECOND_CYCLES-1 := 0;
   signal index : natural range 0 to 8 := 0;
   signal second_pass : boolean := false;
   signal first, second, last_hardware : bytes_t := (others => (others => '0'));
   signal seen_hardware : boolean := false;
   signal data_meta, data_sync : std_logic_vector(7 downto 0) := (others => '0');
   attribute ASYNC_REG : string;
   attribute ASYNC_REG of data_meta, data_sync : signal is "TRUE";
   signal sec, minute : natural range 0 to 59 := 0;
   signal hour : natural range 0 to 23 := 0;
   signal day : natural range 1 to 31 := 1;
   signal month : natural range 1 to 12 := 1;
   signal year, century : natural range 0 to 99 := 0;
   signal weekday : natural range 0 to 6 := 6;
   signal toggle : std_logic := '0';

   function bcd(n : natural) return std_logic_vector is
   begin
      return std_logic_vector(to_unsigned(n / 10, 4) & to_unsigned(n mod 10, 4));
   end;
   function number(v : std_logic_vector(7 downto 0)) return natural is
   begin
      return to_integer(unsigned(v(7 downto 4))) * 10 + to_integer(unsigned(v(3 downto 0)));
   end;
   function valid_bcd(v : std_logic_vector(7 downto 0); lo, hi : natural) return boolean is
   begin
      if is_x(v) then return false; end if;
      return unsigned(v(7 downto 4)) <= 9 and unsigned(v(3 downto 0)) <= 9
         and number(v) >= lo and number(v) <= hi;
   end;
   function days_in_month(m, y, c : natural) return natural is
   begin
      case m is
         when 4 | 6 | 9 | 11 => return 30;
         when 2 =>
            if y mod 4 = 0 and (y /= 0 or c mod 4 = 0) then return 29; end if;
            return 28;
         when others => return 31;
      end case;
   end;
   function valid_snapshot(v : bytes_t) return boolean is
   begin
      if not (valid_bcd(v(0),0,59) and valid_bcd(v(1),0,59)
         and valid_bcd(v(3),1,31) and valid_bcd(v(4),1,7)
         and valid_bcd(v(5),1,12) and valid_bcd(v(6),0,99)
         and valid_bcd(v(7),0,99)) then return false; end if;
      if is_x(v(2)) or is_x(v(8)) or v(8)(7 downto 4) /= "0000" or v(8)(3) /= '0' then
         return false; -- UTI set: hardware registers are explicitly frozen.
      end if;
      if v(8)(1) = '1' then
         if not valid_bcd(v(2),0,23) then return false; end if;
      else
         if not valid_bcd('0' & v(2)(6 downto 0),1,12) then return false; end if;
      end if;
      return number(v(3)) <= days_in_month(number(v(5)),number(v(6)),number(v(7)));
   end;
begin
   -- 1 us setup, 1 us read (150 ns worst-case access), 1 us recovery
   -- (60 ns worst-case release). External data is sampled after 2 FFs settle.
   address_o <= std_logic_vector(to_unsigned(C_ADDR(index),4));
   bus_owned_o <= '0' when state = startup else '1';
   cs_n_o <= '0' when state = reading else '1';
   oe_n_o <= '0' when state = reading else '1';
   rtc_o <= toggle & X"40" & bcd(weekday) & bcd(year) & bcd(month)
            & bcd(day) & bcd(hour) & bcd(minute) & bcd(sec);

   process(clk_i)
      variable h : natural range 0 to 99;
   begin
      if rising_edge(clk_i) then
         data_meta <= data_i;
         data_sync <= data_meta;
         if second_count = G_SECOND_CYCLES-1 then
            second_count <= 0;
            toggle <= not toggle;
            if sec < 59 then sec <= sec+1;
            else
               sec <= 0;
               if minute < 59 then minute <= minute+1;
               else
                  minute <= 0;
                  if hour < 23 then hour <= hour+1;
                  else
                     hour <= 0;
                     weekday <= (weekday+1) mod 7;
                     if day < days_in_month(month,year,century) then day <= day+1;
                     else
                        day <= 1;
                        if month < 12 then month <= month+1;
                        else
                           month <= 1;
                           if year < 99 then year <= year+1;
                           else year <= 0; century <= (century+1) mod 100;
                           end if;
                        end if;
                     end if;
                  end if;
               end if;
            end if;
         else second_count <= second_count+1;
         end if;

         case state is
            when startup =>
               if start_count = G_START_CYCLES-1 then state <= idle;
               else start_count <= start_count+1; end if;
            when idle =>
               if poll_count = G_POLL_CYCLES-1 then
                  poll_count <= 0; index <= 0; second_pass <= false;
                  phase <= 0; state <= setup_address;
               else poll_count <= poll_count+1; end if;
            when setup_address =>
               if phase = G_PHASE_CYCLES-1 then phase <= 0; state <= reading;
               else phase <= phase+1; end if;
            when reading =>
               if phase = G_PHASE_CYCLES-1 then
                  if second_pass then second(index) <= data_sync;
                  else first(index) <= data_sync; end if;
                  phase <= 0; state <= recovery;
               else phase <= phase+1; end if;
            when recovery =>
               if phase = G_PHASE_CYCLES-1 then
                  phase <= 0;
                  if index = 8 then
                     if second_pass then state <= check_snapshot;
                     else second_pass <= true; index <= 0; state <= setup_address; end if;
                  else index <= index+1; state <= setup_address; end if;
               else phase <= phase+1; end if;
            when check_snapshot =>
               state <= idle;
               hardware_valid_o <= '0';
               if first = second and valid_snapshot(second) then
                  if not seen_hardware or second /= last_hardware then
                     seen_hardware <= true;
                     last_hardware <= second;
                     hardware_valid_o <= '1';
                     sec <= number(second(0)); minute <= number(second(1));
                     h := number('0' & second(2)(6 downto 0));
                     if second(8)(1) = '0' then
                        h := h mod 12;
                        if second(2)(7) = '1' then h := h+12; end if;
                     end if;
                     hour <= h; day <= number(second(3)); weekday <= number(second(4))-1;
                     month <= number(second(5)); year <= number(second(6)); century <= number(second(7));
                     second_count <= 0; toggle <= not toggle;
                  end if;
               end if;
         end case;

         if rst_i = '1' then
            state <= startup; phase <= 0; start_count <= 0; poll_count <= 0;
            index <= 0; second_pass <= false; seen_hardware <= false;
            first <= (others => (others => '0')); second <= (others => (others => '0'));
            last_hardware <= (others => (others => '0'));
            second_count <= 0; toggle <= '0'; hardware_valid_o <= '0';
            sec <= 0; minute <= 0; hour <= 0; day <= 1; month <= 1;
            year <= 0; century <= 20; weekday <= 6; -- 2000-01-01 Saturday
         end if;
      end if;
   end process;
end architecture;
