--
-- WWW.FPGAArcade.COM
--
-- REPLAY Retro Gaming Platform
-- No Emulation No Compromise
--
-- std_logic rights reserved
-- Mike Johnson 2015
--
-- Redistribution and use in source and synthezised forms, with or without
-- modification, are permitted provided that the following conditions are met:
--
-- Redistributions of source code must retain the above copyright notice,
-- this list of conditions and the following disclaimer.
--
-- Redistributions in synthesized form must reproduce the above copyright
-- notice, this list of conditions and the following disclaimer in the
-- documentation and/or other materials provided with the distribution.
--
-- Neither the name of the author nor the names of other contributors may
-- be used to endorse or promote products derived from this software without
-- specific prior written permission.
--
-- THIS CODE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
-- AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
-- THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
-- PURPOSE ARE DISCLAIMED. IN NO EVENT SHstd_logic THE AUTHOR OR CONTRIBUTORS BE
-- LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
-- CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
-- SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
-- INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
-- CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
-- ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
-- POSSIBILITY OF SUCH DAMAGE.
--
-- You are responsible for any legal issues arising from your use of this code.
--
-- The latest version of this file can be found at: www.FPGAArcade.com
--
-- Email support@fpgaarcade.com
--

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.std_logic_unsigned.all;
  use ieee.numeric_std.all;

entity m6581_Voice is
  port (
    --
    i_clk                 : in  std_logic;
    i_ena                 : in  std_logic;
    i_rst                 : in  std_logic;
    --
    --i_reg                 : in  r_voice_reg;
	 Freq_lo			: in	unsigned(7 downto 0);	-- low-byte of frequency register 
	 Freq_hi			: in	unsigned(7 downto 0);	-- high-byte of frequency register 
	 Pw_lo				: in	unsigned(7 downto 0);	-- low-byte of PuleWidth register
	 Pw_hi				: in	unsigned(3 downto 0);	-- high-nibble of PuleWidth register
	 Control			: in	unsigned(7 downto 0);	-- control register
	 Att_dec			: in	unsigned(7 downto 0);	-- attack-deccay register
	 Sus_Rel			: in	unsigned(7 downto 0);	-- sustain-release register

    --
    o_osc                 : out std_logic_vector( 7 downto 0);
    o_env                 : out std_logic_vector( 7 downto 0);
    --
    i_msb                 : in  std_logic;
    o_msb                 : out std_logic;
    --
    o_wave                : out std_logic_vector(19 downto 0) -- signed
    );
end;

architecture RTL of m6581_Voice is
  --
  signal msb_in_t1              : std_logic;
  signal accum                  : std_logic_vector(23 downto 0);
  signal accum_t1               : std_logic_vector(23 downto 0);
  signal wave_saw               : std_logic_vector(11 downto 0);
  signal wave_sqr               : std_logic_vector(11 downto 0);
  signal wave_tri               : std_logic_vector(11 downto 0);
  signal lfsr_reg               : std_logic_vector(22 downto 0) := "11111111111111111111111";
  signal lfsr                   : std_logic_vector(22 downto 0);
  signal noise                  : std_logic_vector(11 downto 0);
  signal mux                    : std_logic_vector(11 downto 0);
  signal mux_signed             : std_logic_vector(11 downto 0);
  signal wave_debug             : std_logic_vector(11 downto 0);
  --
  signal op_mul_p               : std_logic_vector(35 downto 0);
  signal op_mul_a               : std_logic_vector(17 downto 0);
  signal op_mul_b               : std_logic_vector(17 downto 0);
  --
  signal env_lfsr_match         : std_logic_vector(15 downto 0);
  signal env_lfsr               : std_logic_vector(14 downto 0);
  signal env_lfsr_next          : std_logic;
  signal env_rate_ena           : std_logic;
  --
  signal log_sel                : std_logic_vector(6 downto 0);
  signal log_sel_reg            : std_logic_vector(4 downto 0);
  signal log_sel_match          : std_logic_vector(4 downto 0);
  signal log_lfsr               : std_logic_vector(4 downto 0);
  signal log_ena                : std_logic;
  --
  signal sustain_match          : std_logic;
  signal env_eq_ff              : std_logic;
  signal env_eq_00              : std_logic;

  signal env_ena                : std_logic;
  signal env_cnt_ena            : std_logic;
  signal env_cnt_down           : std_logic;
  signal env                    : std_logic_vector( 7 downto 0);

  type t_adsr is (S_IDLE, S_ATTACK, S_DECAY, S_RELEASE);
  signal adsr_cur_s             : t_adsr;
  signal adsr_next_s            : t_adsr;

begin

  p_phase_accum : process(i_clk, i_rst)
    variable do_sync : boolean;
  begin
    if (i_rst = '1') then
      accum     <= (others => '0');
      msb_in_t1 <= '0';
      accum_t1  <= (others => '0');
    elsif rising_edge(i_clk) then
      if (i_ena = '1') then
        msb_in_t1 <= i_msb;

        do_sync := (i_msb = '0') and (msb_in_t1 = '1') and (control(1) = '1');

        if (control(3) = '1') or (do_sync) then
          accum <= (others => '0');
        else
          accum <= accum + (x"00" & Freq_hi &  Freq_lo ) + '1';
        end if;

        accum_t1 <= accum;
      end if;
    end if;
  end process;
  o_msb <= accum(23);

  p_saw : process(accum)
  begin
    wave_saw <= accum(23 downto 12);
  end process;

  p_sqr : process(accum, i_reg)
  begin
    wave_sqr <= (others => '0');
    if ((accum(23 downto 12)) >= (i_reg.pw(11 downto 0))) then
      wave_sqr <= (others => '1');
    end if;
  end process;

  p_tri : process(accum, i_reg, i_msb)
    variable msb : std_logic;
  begin
    if (i_reg.control.ringmod = '0') then
      msb := accum(23);
    else
      msb := i_msb;
    end if;

    for i in 0 to 11 loop
      wave_tri(i) <= msb xor accum(11+i);
    end loop;
  end process;

  p_lfsr_reg : process
    variable shift : std_logic;
  begin
    wait until rising_edge(i_clk);
    shift := accum(19) and (not accum_t1(19));  -- rising edge only?

    if (i_ena = '1') then
      if (i_reg.control.test = '0') and (shift = '1') then -- clock
        lfsr_reg <= lfsr;
      end if;
    end if;
  end process;

  -- feedback of LFSR from possible shorted DAC MUX lines (if multiple channels are enabled)
  lfsr <= lfsr_reg(21) &
          mux(11) &
          lfsr_reg(19) &
          mux(10) &
          lfsr_reg(17 downto 15) &
          mux(9) &
          lfsr_reg(13 downto 12) &
          mux(8) &
          lfsr_reg(10) &
          mux(7) &
          lfsr_reg(8 downto 6) &
          mux(6) &
          lfsr_reg(4 downto 3) &
          mux(5) &
          lfsr_reg(1) &
          mux(4) &
          (lfsr_reg(17) xor (lfsr_reg(22) or i_rst or i_reg.control.test));

  -- enabling noise on #3 /w freq=0 gives 0xFF in OSC3 reg, so it must come from the reg., not the feedback (which gives 0xF7)
  noise <= lfsr_reg(20) & lfsr_reg(18) & lfsr_reg(14) & lfsr_reg(11) & lfsr_reg(9) & lfsr_reg(5) & lfsr_reg(2) & lfsr_reg(0) & "0000";

  -- this combination is quite complex and only a very rough (pure logical) substitution...
  -- it is based on the fact that enabling multiple channels short them towards zero (but it is not a perfect logical AND as done here)
  p_wave_select : process
  begin
    wait until rising_edge(i_clk);
    if (i_ena = '1') then
      for i in 0 to 11 loop
        -- single channels
        if i_reg.control.noise='1' and i_reg.control.wave_sqr='0' and i_reg.control.wave_saw='0' and i_reg.control.wave_tri='0' then
          mux(i) <= noise(i);
        elsif i_reg.control.noise='0' and i_reg.control.wave_sqr='1' and i_reg.control.wave_saw='0' and i_reg.control.wave_tri='0' then
          mux(i) <= wave_sqr(i);
        elsif i_reg.control.noise='0' and i_reg.control.wave_sqr='0' and i_reg.control.wave_saw='1' and i_reg.control.wave_tri='0' then
          mux(i) <= wave_saw(i);
        elsif i_reg.control.noise='0' and i_reg.control.wave_sqr='0' and i_reg.control.wave_saw='0' and i_reg.control.wave_tri='1' then
          mux(i) <= wave_tri(i);
        -- shorting 2 channels
        elsif i_reg.control.noise='1' and i_reg.control.wave_sqr='1' and i_reg.control.wave_saw='0' and i_reg.control.wave_tri='0' then
          mux(i) <= noise(i) and wave_sqr(i);
        elsif i_reg.control.noise='1' and i_reg.control.wave_sqr='0' and i_reg.control.wave_saw='1' and i_reg.control.wave_tri='0' then
          mux(i) <= noise(i) and wave_saw(i);
        elsif i_reg.control.noise='1' and i_reg.control.wave_sqr='0' and i_reg.control.wave_saw='0' and i_reg.control.wave_tri='1' then
          mux(i) <= noise(i) and wave_tri(i);
        elsif i_reg.control.noise='0' and i_reg.control.wave_sqr='1' and i_reg.control.wave_saw='1' and i_reg.control.wave_tri='0' then
          mux(i) <= wave_sqr(i) and wave_saw(i);
        elsif i_reg.control.noise='0' and i_reg.control.wave_sqr='1' and i_reg.control.wave_saw='0' and i_reg.control.wave_tri='1' then
          mux(i) <= wave_sqr(i) and wave_tri(i);
        elsif i_reg.control.noise='0' and i_reg.control.wave_sqr='0' and i_reg.control.wave_saw='1' and i_reg.control.wave_tri='1' then
          mux(i) <= wave_saw(i) and wave_tri(i);
        -- shorting 3 channels
        elsif i_reg.control.noise='1' and i_reg.control.wave_sqr='1' and i_reg.control.wave_saw='1' and i_reg.control.wave_tri='0' then
          mux(i) <= noise(i) and wave_sqr(i) and wave_saw(i);
        elsif i_reg.control.noise='1' and i_reg.control.wave_sqr='1' and i_reg.control.wave_saw='0' and i_reg.control.wave_tri='1' then
          mux(i) <= noise(i) and wave_sqr(i) and wave_tri(i);
        elsif i_reg.control.noise='1' and i_reg.control.wave_sqr='0' and i_reg.control.wave_saw='1' and i_reg.control.wave_tri='1' then
          mux(i) <= noise(i) and wave_saw(i) and wave_tri(i);
        elsif i_reg.control.noise='0' and i_reg.control.wave_sqr='1' and i_reg.control.wave_saw='1' and i_reg.control.wave_tri='1' then
          mux(i) <= wave_sqr(i) and wave_saw(i) and wave_tri(i);
        -- shorting std_logic channels
        elsif  i_reg.control.noise='1' and i_reg.control.wave_sqr='1' and i_reg.control.wave_saw='1' and i_reg.control.wave_tri='1' then
          mux(i) <= noise(i) and wave_sqr(i) and wave_saw(i) and wave_tri(i);
        -- no channel
        else
          mux(i) <= '0';
        end if;
      end loop;
    end if;
  end process;

  -- red_and (input or not enable)
  -- THIS is where the DAC would go. May need table to model below

  --// Build DAC lookup tables for 12-bit DACs.
  --// MOS 6581: 2R/R ~ 2.20, missing termination resistor.
  --build_dac_table(model_dac[0], 12, 2.20, false);
  --// MOS 8580: 2R/R ~ 2.00, correct termination.
  --build_dac_table(model_dac[1], 12, 2.00, true);

  --// The SID DACs are built up as follows:
  --//
  --//          n  n-1      2   1   0    VGND
  --//          |   |       |   |   |      |   Termination
  --//         2R  2R      2R  2R  2R     2R   only for
  --//          |   |       |   |   |      |   MOS 8580
  --//      Vo  --R---R--...--R---R--    ---
  --//
  --//
  --// std_logic MOS 6581 DACs are missing a termination resistor at bit 0. This causes
  --// pronounced errors for the lower 4 - 5 bits (e.g. the output for bit 0 is
  --// actustd_logicy equal to the output for bit 1), resulting in DAC discontinuities
  --// for the lower bits.
  --// In addition to this, the 6581 DACs exhibit further severe discontinuities
  --// for higher bits, which may be explained by a less than perfect match between
  --// the R and 2R resistors, or by output impedance in the NMOS transistors -
  --// providing the bit voltages. A good approximation of the actual DAC output is
  --// achieved for 2R/R ~ 2.20.
  --//
  --// The MOS 8580 DACs, on the other hand, do not exhibit any discontinuities.
  --// These DACs include the correct termination resistor, and also seem to have
  --// very accurately matched R and 2R resistors (2R/R = 2.00).

  o_osc <= mux(11 downto 4);

  -- I'm not sure where the center point is.
  -- it would make sense if the midpoint is taken as "0" and the ADSR volume
  -- multiplier would be modulate both halves of the cycle.
  --
  -- flip top bit to convert to 2s comp

  -- 255 = 11111111 => 01111111 +127
  -- 129 = 10000001 => 00000001 +1
  -- 128 = 10000000 => 00000000  0
  -- 127 = 01111111 => 11111111 -1
  --   0 = 00000000 => 10000000 -128

  mux_signed <= (not mux(11)) & mux(10 downto 0);

  op_mul_a <= mux_signed & "000000";
  op_mul_b <= "00" & x"00" & env;
  -- we could move this outside the voice generator and share one multiplier between the chans
  u_op_mul : MULT18X18
  port map (
     P => op_mul_p,
     A => op_mul_a,
     B => op_mul_b
  );
  o_wave     <= op_mul_p(25 downto 25-20+1);
  wave_debug <= op_mul_p(25 downto 25-12+1);
  --
  -- ADSR
  --

  p_env_table : process(i_reg, adsr_cur_s)
    variable rate : std_logic_vector(3 downto 0);
  begin

    rate := i_reg.attack;
    if (adsr_cur_s = S_DECAY)   then rate := i_reg.decay;   end if;
    if (adsr_cur_s = S_RELEASE) then rate := i_reg.release; end if;

    env_lfsr_match <= x"7F00"; -- default
    case rate is
      when x"0" => env_lfsr_match <= x"7F00";
      when x"1" => env_lfsr_match <= x"0006";
      when x"2" => env_lfsr_match <= x"003C";
      when x"3" => env_lfsr_match <= x"0330";
      when x"4" => env_lfsr_match <= x"20C0";
      when x"5" => env_lfsr_match <= x"6755";
      when x"6" => env_lfsr_match <= x"3800";
      when x"7" => env_lfsr_match <= x"500E";
      when x"8" => env_lfsr_match <= x"1212";
      when x"9" => env_lfsr_match <= x"0222";
      when x"A" => env_lfsr_match <= x"1848";
      when x"B" => env_lfsr_match <= x"59B8";
      when x"C" => env_lfsr_match <= x"3840";
      when x"D" => env_lfsr_match <= x"77E2";
      when x"E" => env_lfsr_match <= x"7625";
      when x"F" => env_lfsr_match <= x"0A93";
      when others => null;
    end case;
  end process;

  p_env_lfsr_match : process(env_lfsr_match, env_lfsr)
  begin
    env_lfsr_next <= '0';
    if (env_lfsr_match(14 downto 0) = env_lfsr) then
      env_lfsr_next <= '1';
    end if;
  end process;

  p_adsr_lfsr : process(i_clk, i_rst)
  begin
    if (i_rst = '1') then
      env_lfsr     <= (others => '1');
      env_rate_ena <= '0';
    elsif rising_edge(i_clk) then
      if (i_ena = '1') then
        env_lfsr <= env_lfsr(13 downto 0) & (env_lfsr(14) xor env_lfsr(13));
        env_rate_ena <= '0';
        if (env_lfsr_next = '1') then
          env_lfsr     <= (others => '1');
          env_rate_ena <= '1';
        end if;
      end if;
    end if;
  end process;


-- Logarithmic Table

  p_log_sel : process(env)
  begin
    log_sel <= "0000000";
    case env is
      when x"00" => log_sel(5) <= '1';
      when x"06" => log_sel(4) <= '1';
      when x"0E" => log_sel(3) <= '1';
      when x"1A" => log_sel(2) <= '1';
      when x"36" => log_sel(1) <= '1';
      when x"5D" => log_sel(0) <= '1';
      when x"FF" => log_sel(6) <= '1';
      when others => null;
    end case;
  end process;

--Selector bit|
--Signal line | "Reset" signal lines
--0             1, 6
--1             0, 2
--2             1, 3
--3             2, 4
--4             3, 5


  p_log_sel_reg : process(i_clk, i_rst)
    variable r1 : natural;
    variable r2 : natural;
  begin
    if (i_rst = '1') then
      log_sel_reg <= (others => '0');
    elsif rising_edge(i_clk) then
      if (i_ena = '1') then
        for i in 0 to 4 loop
          case i is
            when 0 => r1:=1; r2:=6;
            when 1 => r1:=0; r2:=2;
            when 2 => r1:=1; r2:=3;
            when 3 => r1:=2; r2:=4;
            when 4 => r1:=3; r2:=5;
            when others => null;
          end case;

          if    (log_sel(r1) = '1') or (log_sel(r2) = '1') then
            log_sel_reg(i) <= '0';
          elsif (log_sel(i) = '1') then
            log_sel_reg(i) <= '1';
          end if;
        end loop;
      end if;
    end if;
  end process;

  p_log_table : process(log_sel_reg)
    variable match : std_logic_vector(7 downto 0);
  begin

    --     0x1B,0x1E,0x11,0x02,0x07   from die
    -- some confusion about order, fixed below?
    match := x"FF";
    if (log_sel_reg(0) = '1') then match := x"1E"; end if;
    if (log_sel_reg(1) = '1') then match := x"11"; end if;
    if (log_sel_reg(2) = '1') then match := x"1B"; end if;
    if (log_sel_reg(3) = '1') then match := x"02"; end if;
    if (log_sel_reg(4) = '1') then match := x"07"; end if;

    log_sel_match <= match(4 downto 0);
  end process;

  p_log_lfsr : process(i_clk, i_rst)
  begin
    if (i_rst = '1') then
      log_lfsr <= (others => '1');
      log_ena  <= '0';
    elsif rising_edge(i_clk) then
      if (i_ena = '1') and (env_rate_ena = '1') then
        log_lfsr <= log_lfsr(3 downto 0) & (log_lfsr(2) xor log_lfsr(4));
        log_ena  <= '0';
        if (log_lfsr = log_sel_match) then
          log_lfsr <= (others => '1');
          log_ena  <= '1';
        end if;
      end if;
    end if;
  end process;

  p_env_ena : process(env_rate_ena, log_ena, adsr_cur_s)
  begin
    -- "attack is linear"
    env_ena <= env_rate_ena;
    if (adsr_cur_s = S_DECAY) or (adsr_cur_s = S_RELEASE) then
      env_ena <= env_rate_ena and log_ena;
    end if;
  end process;

  p_env_match : process(env, i_reg)
  begin
    sustain_match <= '0';
    if ((i_reg.sustain & i_reg.sustain) = env) then
      sustain_match <= '1';
    end if;
    env_eq_ff <= '0';
    if (env = x"FF") then
      env_eq_ff <= '1';
    end if;

    env_eq_00 <= '0';
    if (env = x"00") then
      env_eq_00 <= '1';
    end if;
  end process;

  p_env_ctrl : process(adsr_cur_s, i_reg, env_eq_ff, env_eq_00, sustain_match)
  begin
    adsr_next_s   <= adsr_cur_s;
    env_cnt_ena  <= '0';
    env_cnt_down <= '0';

    case adsr_cur_s is
      when S_IDLE =>
        if (i_reg.control.gate = '1') then adsr_next_s <= S_ATTACK; end if;

      when S_ATTACK =>
        env_cnt_ena  <= '1';
        env_cnt_down <= '0';
        if (i_reg.control.gate = '0') then adsr_next_s <= S_RELEASE; end if;

        if (env_eq_ff = '1') then
          env_cnt_ena <= '0';
          adsr_next_s <= S_DECAY;
        end if;

      when S_DECAY =>
        env_cnt_ena  <= '1';
        env_cnt_down <= '1';
        if (i_reg.control.gate = '0') then adsr_next_s <= S_RELEASE; end if;

        if (sustain_match = '1') then
          env_cnt_ena <= '0';
        end if;

      when S_RELEASE =>
        env_cnt_ena  <= '1';
        env_cnt_down <= '1';
        if (env_eq_00 = '1') then
          env_cnt_ena  <= '0';
          adsr_next_s <= S_IDLE;
        end if;

        if (i_reg.control.gate = '1') then adsr_next_s <= S_ATTACK; end if;

      when others => null;
    end case;
  end process;

  p_env_state : process(i_clk, i_rst)
  begin
    if (i_rst = '1') then
      adsr_cur_s <= S_IDLE;
    elsif rising_edge(i_clk) then
      if (i_ena = '1') then
        adsr_cur_s <= adsr_next_s;
      end if;
    end if;
  end process;

  p_env : process(i_clk, i_rst)
    variable offset : std_logic_vector(7 downto 0);
  begin
    if (i_rst = '1') then
      env <= (others => '0');
    elsif rising_edge(i_clk) then
      if (i_ena = '1') then
        offset := "00000000";
        if (env_cnt_ena = '1') and (env_ena = '1') then
          offset := "00000001";
          if (env_cnt_down = '1') then
            offset := "11111111";
          end if;
        end if;
        env <= env + offset;
      end if;
    end if;
  end process;

  o_env <= env;
end RTL;
