library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity square_wave_440hz is
    port (
        clk : in std_logic;
        ce_48k : in std_logic;
        reset : in std_logic;
        audio_out : out std_logic_vector (23 downto 0)
    );
end square_wave_440hz;

architecture Behavioral of square_wave_440hz is

    signal phase_accumulator : unsigned(31 downto 0) := (others => '0');

    constant TUNING_WORD : unsigned(31 downto 0) := x"0258A3E6";
    -- Amplitude (Signed 16-bit audio)
    -- 25% volume 
    constant AMP_HIGH : std_logic_vector(23 downto 0) := x"010000"; -- Positive peak
    constant AMP_LOW : std_logic_vector(23 downto 0) := x"FFFFFF"; -- Negative peak (2's complement)
begin
    process (clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                phase_accumulator <= (others => '0');
            elsif ce_48k = '1' then
                phase_accumulator <= phase_accumulator + TUNING_WORD;
            end if;
        end if;
    end process;

    audio_out <= AMP_HIGH when phase_accumulator(31) = '1' else
        AMP_LOW;

end Behavioral;