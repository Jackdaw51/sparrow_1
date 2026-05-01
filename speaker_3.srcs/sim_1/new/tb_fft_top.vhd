library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all; -- This allows us to generate a perfect sine wave!

entity tb_fft_top is
-- Testbenches never have ports!
end tb_fft_top;

architecture sim of tb_fft_top is

    -- 100 MHz clock period
    constant CLK_PERIOD : time := 10 ns;
    
    -- Signals to connect to your fft_top module
    signal clk          : std_logic := '0';
    signal reset        : std_logic := '1';
    signal adc_valid_in : std_logic := '0';
    signal audio_data   : std_logic_vector(23 downto 0) := (others => '0');
    signal peak_freq_hz : std_logic_vector(15 downto 0);
    
    -- Sine wave parameters
    constant FS         : real := 48000.0; -- 48 kHz sample rate
    constant F_TONE     : real := 440.0;   -- 440 Hz target frequency
    constant AMPLITUDE  : real := 8388607.0; -- 24-bit max amplitude (standard for I2S audio)

begin

    -- Instance of your top-level module
    -- (Make sure these port names match your actual fft_top.vhd!)
    UUT: entity work.fft_top
    port map (
        clk          => clk,
        reset        => reset,
        adc_valid_in => adc_valid_in,
        adc_data_in   => audio_data,
        peak_freq_hz => peak_freq_hz
    );

    -- Clock Generation Process (100 MHz)
    clk_process: process
    begin
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    -- Stimulus Process: This generates the audio and the valid pulses
    stim_proc: process
        variable t : real := 0.0;
        variable sample_val_real : real;
        variable sample_val_int  : integer;
    begin
        -- 1. Apply Reset
        reset <= '1';
        adc_valid_in <= '0';
        wait for 100 ns;
        reset <= '0';
        wait for 100 ns;

        -- 2. Generate 10,000 samples 
        -- (We need at least 8192 to fill the ping-pong buffer once!)
        -- integrate_and_dump module takes 10 adc_valid_in samples to produce 1 valid_out.
        -- To fill one bank of your 8,192-depth ping-pong BRAM, you need 8192 * 10 
        -- =81,920 samples. So 100000
        for i in 0 to 100000 loop
            
            -- Calculate the exact time 't' for this sample index
            t := real(i) / FS;
            
            -- Calculate: Amplitude * sin(2 * pi * f * t)
            sample_val_real := AMPLITUDE * sin(MATH_2_PI * F_TONE * t);
            
            -- Convert the floating-point decimal to a 32-bit hardware integer
            sample_val_int := integer(sample_val_real);
            audio_data <= std_logic_vector(to_signed(sample_val_int, 24));
            
            -- 3. Strobe adc_valid_in for exactly ONE 100 MHz clock cycle
            adc_valid_in <= '1';
            wait for CLK_PERIOD;
            adc_valid_in <= '0';
            
            wait for CLK_PERIOD;
            
        end loop;

        -- End the simulation beautifully
        report "SIMULATION COMPLETE: A full frame was sent." severity note;
        wait; 
    end process;

end sim;