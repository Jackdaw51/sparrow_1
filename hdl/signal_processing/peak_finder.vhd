library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity peak_finder is
    port (
        clk           : in  std_logic;
        reset         : in  std_logic;
        
        -- From FFT IP (m_axis_data)
        s_axis_tdata  : in  std_logic_vector(63 downto 0); -- [31:0] Imag, [63:32] Real
        s_axis_tvalid : in  std_logic;
        s_axis_tlast  : in  std_logic;
        
        -- Final Result
        peak_bin_index : out std_logic_vector(12 downto 0); -- The "Bucket" number
        peak_ready     : out std_logic                      -- Pulses when frame is done
    );
end peak_finder;

architecture Behavioral of peak_finder is

    -- Internal signals for math
    signal real_part : signed(31 downto 0);
    signal imag_part : signed(31 downto 0);
    signal pwr_real  : signed(63 downto 0);
    signal pwr_imag  : signed(63 downto 0);
    signal pwr_sum   : signed(63 downto 0);
    
    -- Search registers
    signal current_bin : unsigned(12 downto 0) := (others => '0');
    signal max_pwr     : signed(63 downto 0)   := (others => '0');
    signal best_bin    : std_logic_vector(12 downto 0) := (others => '0');

begin

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                max_pwr <= (others => '0');
                current_bin <= (others => '0');
                peak_ready <= '0';
            else
                peak_ready <= '0'; -- Pulse by default

                if s_axis_tvalid = '1' then
                    -- 1. Split and Square (Power Calculation)
                    real_part <= signed(s_axis_tdata(63 downto 32));
                    imag_part <= signed(s_axis_tdata(31 downto 0));
                    
                    pwr_real <= real_part * real_part;
                    pwr_imag <= imag_part * imag_part;
                    pwr_sum  <= pwr_real + pwr_imag;

                    -- 2. Compare to current "High Score"
                    -- Note: We add a 2-cycle latency here to wait for multipliers
                    if pwr_sum > max_pwr then
                        max_pwr  <= pwr_sum;
                        best_bin <= std_logic_vector(current_bin);
                    end if;

                    -- 3. Increment bin counter
                    if s_axis_tlast = '1' then
                        peak_bin_index <= best_bin; -- Final Answer for this frame
                        peak_ready     <= '1';
                        
                        -- Reset for next 8192-point burst
                        max_pwr     <= (others => '0');
                        current_bin <= (others => '0');
                    else
                        current_bin <= current_bin + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

end Behavioral;