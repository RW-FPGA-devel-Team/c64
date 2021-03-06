-------------------------------------------------------------------------------
--
--                                 SID 8580 (voice)
--
--     This piece of VHDL code describes a single SID voice (sound channel)
--
-------------------------------------------------------------------------------
--	to do:	- better resolution of result signal voice, this is now only 12bits
--	but it could be 20 !! Problem, it does not fit the PWM-dac
-------------------------------------------------------------------------------

library IEEE;
	use IEEE.std_logic_1164.all;
	--use IEEE.std_logic_arith.all;
	use IEEE.std_logic_unsigned.all;
	use IEEE.numeric_std.all;

-------------------------------------------------------------------------------

entity sid8580_voice is
	port (
	   clk32          : in  std_logic;
		clk_1MHz			: in	std_logic;							-- this line drives the oscilator
		reset				: in	std_logic;							-- active high signal (i.e. registers are reset when reset=1)
		Freq_lo			: in	unsigned(7 downto 0);	-- low-byte of frequency register 
		Freq_hi			: in	unsigned(7 downto 0);	-- high-byte of frequency register 
		Pw_lo				: in	unsigned(7 downto 0);	-- low-byte of PuleWidth register
		Pw_hi				: in	unsigned(3 downto 0);	-- high-nibble of PuleWidth register
		Control			: in	unsigned(7 downto 0);	-- control register
		Att_dec			: in	unsigned(7 downto 0);	-- attack-deccay register
		Sus_Rel			: in	unsigned(7 downto 0);	-- sustain-release register
		PA_MSB_in		: in	std_logic;							-- Phase Accumulator MSB input
		PA_MSB_out		: out	std_logic;							-- Phase Accumulator MSB output
		
		w_st_out  		: in unsigned(7 downto 0);
		w_p_t_out  		: in unsigned(7 downto 0);
		w_ps_out  		: in unsigned(7 downto 0);
		w_pst_out  		: in unsigned(7 downto 0);
		
		triangle  		: buffer unsigned(11 downto 0);
		sawtooth  		: buffer unsigned(11 downto 0);


		Osc				: out	unsigned(7 downto 0);	-- Voice waveform register
		Env				: out	unsigned(7 downto 0);	-- Voice envelope register
		voice				: out	unsigned(11 downto 0)	-- Voice waveform, this is the actual audio signal
	);
end sid8580_voice;

architecture Behavioral of sid8580_voice is	

-------------------------------------------------------------------------------
--	Altera multiplier
--	COMPONENT lpm_mult
--	GENERIC
--	(
--		lpm_hint		: STRING;
--		lpm_representation		: STRING;
--		lpm_type		: STRING;
--		lpm_widtha		: NATURAL;
--		lpm_widthb		: NATURAL;
--		lpm_widthp		: NATURAL;
--		lpm_widths		: NATURAL
--	);
--	PORT 
--	(
--		dataa		: IN	STD_LOGIC_VECTOR (11 DOWNTO 0);
--		datab		: IN	STD_LOGIC_VECTOR (7 DOWNTO 0);
--		result	: OUT	STD_LOGIC_VECTOR (19 DOWNTO 0)
--	);
--	END COMPONENT;

-------------------------------------------------------------------------------

	signal	accumulator					: unsigned(23 downto 0) := (others => '0');
	signal	accu_bit_prev				: std_logic := '0';
	signal	PA_MSB_in_prev				: std_logic := '0';

	-- this type of signal has only two states 0 or 1 (so no more bits are required)
	signal	pulse							: std_logic := '0';
	signal   w_pulse                 : unsigned(11 downto 0);
--	signal	sawtooth						: std_logic_vector(11 downto 0) := (others => '0');
--	signal	triangle						: std_logic_vector(11 downto 0) := (others => '0');
	signal	noise							: unsigned(11 downto 0) := (others => '0');
	signal	LFSR							: unsigned(22 downto 0) := (others => '0');

	signal 	frequency					: unsigned(15 downto 0) := (others => '0');
	signal 	pulsewidth					: unsigned(11 downto 0) := (others => '0');

	-- Envelope Generator
	signal	env_counter					: std_logic_vector(7 downto 0) := (others => '0');

	signal	signal_mux					: unsigned(11 downto 0) := (others => '0');
	signal	signal_vol					: unsigned(19 downto 0) := (others => '0');

	------------------------------------------------------------------------------------
	component sid_envelope
	port (
	   clock    : in std_logic;
		ce_1m  	: in std_logic;
		reset    : in std_logic;
		gate     : in std_logic;
		att_dec	: in std_logic_vector (7 downto 0);
		sus_rel	: in std_logic_vector (7 downto 0);
		envelope : out std_logic_vector(7 downto 0)
   );
	end component sid_envelope;

	-------------------------------------------------------------------------------------

	-- stop the oscillator when test = '1'
	alias		test							: std_logic is Control(3);
	-- Ring Modulation was accomplished by substituting the accumulator MSB of an
	-- oscillator in the EXOR function of the triangle waveform generator with the
	-- accumulator MSB of the previous oscillator. That is why the triangle waveform
	-- must be selected to use Ring Modulation.
	alias		ringmod						: std_logic is Control(2);
	-- Hard Sync was accomplished by clearing the accumulator of an Oscillator
	-- based on the accumulator MSB of the previous oscillator.
	alias		sync							: std_logic is Control(1);
	--
	alias		gate							: std_logic is Control(0);
	
	function repeat(N: natural; B: std_logic)
	  return std_logic_vector
     is
     variable result: std_logic_vector(1 to N);
     begin
       for i in 1 to N loop
       result(i) := B;
     end loop;
     return result;
   end;


-------------------------------------------------------------------------------------

begin

	-- output the Phase accumulator's MSB for sync and ringmod purposes
	PA_MSB_out					<= accumulator(23);
	-- output the upper 8-bits of the waveform.
	-- Useful for random numbers (noise must be selected)
	Osc							<= signal_mux(11 downto 4);
	-- output the envelope register, for special sound effects when connecting this
	-- signal to the input of other channels/voices
	Env							<= unsigned(env_counter);
	-- use the register value to fill the variable
	frequency	<= Freq_hi & Freq_lo;
	-- use the register value to fill the variable
	pulsewidth 	<= Pw_hi & Pw_lo;
	--
	voice							<= signal_vol(19 downto 8);

	-- Phase accumulator :
	-- "As I recall, the Oscillator is a 24-bit phase-accumulating design of which
	-- the lower 16-bits are programmable for pitch control. The output of the
	-- accumulator goes directly to a D/A converter through a waveform selector.
	-- Normally, the output of a phase-accumulating oscillator would be used as an
	-- address into memory which contained a wavetable, but SID had to be entirely
	-- self-contained and there was no room at all for a wavetable on the chip."
	-- "Hard Sync was accomplished by clearing the accumulator of an Oscillator
	-- based on the accumulator MSB of the previous oscillator."
	PhaseAcc:process(clk_1MHz)
	begin
		if (rising_edge(clk_1MHz)) then
			PA_MSB_in_prev <= PA_MSB_in;
			-- the reset and test signal can stop the oscillator,
			-- stopping the oscillator is very useful when you want to play "samples"
			if ((reset = '1') or (test = '1') or ((sync = '1') and (PA_MSB_in_prev /= PA_MSB_in) and (PA_MSB_in = '0'))) then
				accumulator <= (others => '0');
			else
				-- accumulate the new phase (i.o.w. increment env_counter with the freq. value)
				accumulator <= accumulator + ("0" & frequency);
			end if;
		end if;
	end process;

	-- Sawtooth waveform :
	-- "The Sawtooth waveform was created by sending the upper 12-bits of the
	-- accumulator to the 12-bit Waveform D/A."
	Snd_Sawtooth:process(clk_1MHz)
	begin
		if (rising_edge(clk_1MHz)) then
			sawtooth	<= accumulator(23 downto 12);
		end if;
	end process;

	--Pulse waveform :
	-- "The Pulse waveform was created by sending the upper 12-bits of the
	-- accumulator to a 12-bit digital comparator. The output of the comparator was
	-- either a one or a zero. This single output was then sent to all 12 bits of
	-- the Waveform D/A. "
	Snd_pulse:process(clk_1MHz)
	begin
		if (rising_edge(clk_1MHz)) then
		  if (test = '1') then
		    w_pulse <= "111111111111";
			 pulse <= '1';
		  else
			if ((accumulator(23 downto 12)) >= pulsewidth) then
				pulse <= '1';
				w_pulse <= "111111111111";
			else
				pulse <= '0';
				w_pulse <="000000000000";
			end if;
		  end if;
		end if;
	end process;

	--Triangle waveform :
	-- "The Triangle waveform was created by using the MSB of the accumulator to
	-- invert the remaining upper 11 accumulator bits using EXOR gates. These 11
	-- bits were then left-shifted (throwing away the MSB) and sent to the Waveform
	-- D/A (so the resolution of the triangle waveform was half that of the sawtooth,
	-- but the amplitude and frequency were the same). "
	-- "Ring Modulation was accomplished by substituting the accumulator MSB of an
	-- oscillator in the EXOR function of the triangle waveform generator with the
	-- accumulator MSB of the previous oscillator. That is why the triangle waveform
	-- must be selected to use Ring Modulation."
	Snd_triangle:process(clk_1MHz)
	begin
		if (rising_edge(clk_1MHz)) then
			if ringmod = '0' then	
				-- no ringmodulation
				triangle(11)<= accumulator(23) xor accumulator(22);
				triangle(10)<= accumulator(23) xor accumulator(21);
				triangle(9)	<= accumulator(23) xor accumulator(20);
				triangle(8)	<= accumulator(23) xor accumulator(19);
				triangle(7)	<= accumulator(23) xor accumulator(18);
				triangle(6)	<= accumulator(23) xor accumulator(17);
				triangle(5)	<= accumulator(23) xor accumulator(16);
				triangle(4)	<= accumulator(23) xor accumulator(15);
				triangle(3)	<= accumulator(23) xor accumulator(14);
				triangle(2)	<= accumulator(23) xor accumulator(13);
				triangle(1)	<= accumulator(23) xor accumulator(12);
				triangle(0)	<= accumulator(23) xor accumulator(11);
			else
				-- ringmodulation by the other voice (previous voice)
				triangle(11)<= PA_MSB_in xor accumulator(22);
				triangle(10)<= PA_MSB_in xor accumulator(21);
				triangle(9)	<= PA_MSB_in xor accumulator(20);
				triangle(8)	<= PA_MSB_in xor accumulator(19);
				triangle(7)	<= PA_MSB_in xor accumulator(18);
				triangle(6)	<= PA_MSB_in xor accumulator(17);
				triangle(5)	<= PA_MSB_in xor accumulator(16);
				triangle(4)	<= PA_MSB_in xor accumulator(15);
				triangle(3)	<= PA_MSB_in xor accumulator(14);
				triangle(2)	<= PA_MSB_in xor accumulator(13);
				triangle(1)	<= PA_MSB_in xor accumulator(12);
				triangle(0)	<= PA_MSB_in xor accumulator(11);
			end if;
		end if;
	end process;

	--Noise (23-bit Linear Feedback Shift Register, max combinations = 8388607) :
	-- "The Noise waveform was created using a 23-bit pseudo-random sequence
	-- generator (i.e., a shift register with specific outputs fed back to the input
	-- through combinatorial logic). The shift register was clocked by one of the
	-- intermediate bits of the accumulator to keep the frequency content of the
	-- noise waveform relatively the same as the pitched waveforms.
	-- The upper 12-bits of the shift register were sent to the Waveform D/A."

	   noise <= LFSR(20) & LFSR(18) & LFSR(14) & LFSR(11) & LFSR(9) & LFSR(5) & LFSR(2) & LFSR(0) & "0000";
	
	Snd_noise:process(clk_1MHz)
	begin
		if (rising_edge(clk_1MHz)) then
			-- the test signal can stop the oscillator,
			-- stopping the oscillator is very useful when you want to play "samples"
			if ((reset = '1') or (test = '1')) then
				accu_bit_prev		<= '0';
				-- the "seed" value (the value that eventually determines the output
				-- pattern) may never be '0' otherwise the generator "locks up"
				LFSR	<= "00000000000000000000001";
		else
			accu_bit_prev	<= accumulator(19);
			-- when not equal to ...
			if	(accu_bit_prev /= accumulator(19)) then
--				LFSR(22 downto 1)	<= LFSR(21 downto 0);
--				LFSR(0) 					<= LFSR(17) xor LFSR(22);  -- see Xilinx XAPP052 for maximal LFSR taps
	         LFSR <= LFSR(21) 
			           & signal_mux(11)
						  & LFSR(19)
						  & signal_mux(10)
						  & LFSR(17 downto 15)
						  & signal_mux(9)
						  & LFSR(13 downto 12)
						  & signal_mux(8)
						  & LFSR(10)
						  & signal_mux(7)
						  & LFSR(8 downto 6)
						  & signal_mux(6)
						  & LFSR(4 downto 3)
						  & signal_mux(5)
						  & LFSR(1)
						  & signal_mux(4)
						  & (LFSR(17) xor (LFSR(22) or reset or test));
		else
				LFSR	 						<= LFSR;
			end if;
		end if;
		end if;
	end process;

	-- Waveform Output selector (MUX):
	-- "Since all of the waveforms were just digital bits, the Waveform Selector
	-- consisted of multiplexers that selected which waveform bits would be sent
	-- to the Waveform D/A. The multiplexers were single transistors and did not
	-- provide a "lock-out", allowing combinations of the waveforms to be selected.
	-- The combination was actually a logical ANDing of the bits of each waveform,
	-- which produced unpredictable results, so I didn't encourage this, especially
	-- since it could lock up the pseudo-random sequence generator by filling it
	-- with zeroes."
	--





	
	Snd_select:process(clk_1MHz)
	begin
		if (rising_edge(clk_1MHz)) then 
	   	if reset = '1' then
				signal_mux <= (others => '0');
			else
			   
				case control(7 downto 4) is
---				 when "0000" => signal_mux <= (others => '0');
				 when "0001" => signal_mux <= triangle;
				 when "0010" => signal_mux <= sawtooth;
				 when "0011" => signal_mux <= w_st_out & "0000";
				 when "0100" => signal_mux <= w_pulse;
				 when "0101" => signal_mux <= (w_p_t_out & "0000")and w_pulse;
				 when "0110" => signal_mux <= (w_ps_out & "0000")  and w_pulse;
				 when "0111" => signal_mux <= (w_pst_out& "0000")  and w_pulse;
				 when "1000" => signal_mux <= noise;
--				 when "1001" => signal_mux <= triangle and noise ;
--				 when "1010" => signal_mux <= sawtooth and noise;
--				 when "1011" => signal_mux <= (w_st_out & "0000") and noise;
--				 when "1100" => signal_mux <= (repeat(12,pulse)) and noise;
--				 when "1101" => signal_mux <= ((w_p_t_out & "0000")and repeat(12,pulse))  and noise;
--				 when "1110" => signal_mux <= ((w_ps_out & "0000")  and repeat(12,pulse)) and noise;
--				 when "1111" => signal_mux <= ((w_pst_out& "0000")  and repeat(12,pulse)) and noise;
				 
				 when others => signal_mux <= triangle and sawtooth and w_pulse and noise;
				end case; 
			end if;
		end if;
	end process;

	env_v : sid_envelope
	port map (
	     clock    => clk32,
		  ce_1m    => clk_1MHz,
		  reset    => reset,
		  gate     => gate,
		  att_dec  => std_logic_vector(Att_dec),
		  sus_rel  => std_logic_vector(Sus_Rel),
		  envelope => env_counter
	);
	
	
 prog_env:process(clk_1MHz)
        begin 
		    if (rising_edge(clk_1MHz)) then
		     signal_vol      <= signal_mux * unsigned(env_counter);
			 end if;
        end process;

	


end Behavioral;
