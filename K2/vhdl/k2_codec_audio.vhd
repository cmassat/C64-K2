----------------------------------------------------------------------------------
-- K2 audio codec output for AExp.
--
-- The codec is initialized with the same seven control words used by the K2
-- boot ROM.  AExp's 12.288 MHz audio-domain samples are serialized as 16-bit
-- stereo I2S at 48 kHz; the board's exact 24.576 MHz oscillator is forwarded
-- as codec MCLK.
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity k2_codec_audio is
   port (
      clk_100_i     : in  std_logic;
      clk_24_576_i  : in  std_logic;
      rst_i         : in  std_logic;
      audio_clk_i   : in  std_logic;
      audio_reset_i : in  std_logic;
      audio_left_i  : in  signed(15 downto 0);
      audio_right_i : in  signed(15 downto 0);
      codec_mclk_o  : out std_logic;
      codec_bclk_o  : out std_logic;
      codec_lrclk_o : out std_logic;
      codec_data_o  : out std_logic;
      codec_ce_o    : out std_logic;
      codec_cl_o    : out std_logic;
      codec_di_o    : out std_logic
   );
end entity k2_codec_audio;

architecture rtl of k2_codec_audio is

   type t_codec_words is array (0 to 6) of std_logic_vector(15 downto 0);
   constant C_CODEC_WORDS : t_codec_words := (
      x"1A00", x"2A03", x"2301", x"2C07", x"1402", x"1602", x"1845"
   );

   type t_cfg_state is (CFG_WAIT_ST, CFG_LOAD_ST, CFG_HIGH_ST,
                        CFG_LOW_ST, CFG_LATCH_ST, CFG_GAP_ST, CFG_DONE_ST);
   signal cfg_state      : t_cfg_state := CFG_WAIT_ST;
   signal cfg_wait_count : natural range 0 to 100_000 := 0;
   signal cfg_div_count  : natural range 0 to 49 := 0;
   signal cfg_word       : natural range 0 to 6 := 0;
   signal cfg_bit        : natural range 0 to 15 := 15;
   signal codec_ce       : std_logic := '1';
   signal codec_cl       : std_logic := '0';
   signal codec_di       : std_logic := '0';

   signal i2s_div        : natural range 0 to 3 := 0;
   signal i2s_bit        : natural range 0 to 31 := 0;
   signal i2s_bclk       : std_logic := '0';
   signal i2s_lrclk      : std_logic := '0';
   signal i2s_data       : std_logic := '0';
   signal left_latched   : std_logic_vector(15 downto 0) := (others => '0');
   signal right_latched  : std_logic_vector(15 downto 0) := (others => '0');

begin

   codec_mclk_o  <= clk_24_576_i;
   codec_bclk_o  <= i2s_bclk;
   codec_lrclk_o <= i2s_lrclk;
   codec_data_o  <= i2s_data;
   codec_ce_o    <= codec_ce;
   codec_cl_o    <= codec_cl;
   codec_di_o    <= codec_di;

   p_i2s : process (audio_clk_i)
   begin
      if rising_edge(audio_clk_i) then
         if i2s_div = 3 then
            i2s_div <= 0;
            if i2s_bclk = '0' then
               i2s_bclk <= '1';
            else
               i2s_bclk <= '0';

               case i2s_bit is
                  when 0 =>
                     -- LR changes one BCLK before the left MSB; this clock
                     -- still carries the previous frame's right LSB.
                     i2s_lrclk     <= '0';
                     i2s_data      <= right_latched(0);
                     left_latched  <= std_logic_vector(audio_left_i);
                     right_latched <= std_logic_vector(audio_right_i);
                  when 1 to 15 =>
                     i2s_data <= left_latched(16-i2s_bit);
                  when 16 =>
                     i2s_lrclk <= '1';
                     i2s_data  <= left_latched(0);
                  when 17 to 31 =>
                     i2s_data <= right_latched(32-i2s_bit);
               end case;

               if i2s_bit = 31 then
                  i2s_bit <= 0;
               else
                  i2s_bit <= i2s_bit + 1;
               end if;
            end if;
         else
            i2s_div <= i2s_div + 1;
         end if;

         if audio_reset_i = '1' then
            i2s_div       <= 0;
            i2s_bit       <= 0;
            i2s_bclk      <= '0';
            i2s_lrclk     <= '0';
            i2s_data      <= '0';
            left_latched  <= (others => '0');
            right_latched <= (others => '0');
         end if;
      end if;
   end process;

   p_codec_config : process (clk_100_i)
   begin
      if rising_edge(clk_100_i) then
         if cfg_div_count = 49 then
            cfg_div_count <= 0;

            case cfg_state is
               when CFG_WAIT_ST =>
                  if cfg_wait_count = 2000 then
                     cfg_state <= CFG_LOAD_ST;
                  else
                     cfg_wait_count <= cfg_wait_count + 1;
                  end if;

               when CFG_LOAD_ST =>
                  codec_ce <= '1';
                  codec_cl <= '0';
                  cfg_bit  <= 15;
                  codec_di <= C_CODEC_WORDS(cfg_word)(15);
                  cfg_state <= CFG_HIGH_ST;

               when CFG_HIGH_ST =>
                  codec_cl  <= '1';
                  cfg_state <= CFG_LOW_ST;

               when CFG_LOW_ST =>
                  codec_cl <= '0';
                  if cfg_bit = 0 then
                     cfg_state <= CFG_LATCH_ST;
                  else
                     cfg_bit   <= cfg_bit - 1;
                     codec_di  <= C_CODEC_WORDS(cfg_word)(cfg_bit-1);
                     cfg_state <= CFG_HIGH_ST;
                  end if;

               when CFG_LATCH_ST =>
                  codec_ce <= '0';
                  cfg_state <= CFG_GAP_ST;

               when CFG_GAP_ST =>
                  codec_ce <= '1';
                  if cfg_word = 6 then
                     cfg_state <= CFG_DONE_ST;
                  else
                     cfg_word  <= cfg_word + 1;
                     cfg_state <= CFG_LOAD_ST;
                  end if;

               when CFG_DONE_ST =>
                  codec_ce <= '1';
                  codec_cl <= '0';
            end case;
         else
            cfg_div_count <= cfg_div_count + 1;
         end if;

         if rst_i = '1' then
            cfg_state      <= CFG_WAIT_ST;
            cfg_wait_count <= 0;
            cfg_div_count  <= 0;
            cfg_word       <= 0;
            cfg_bit        <= 15;
            codec_ce       <= '1';
            codec_cl       <= '0';
            codec_di       <= '0';
         end if;
      end if;
   end process;

end architecture rtl;
