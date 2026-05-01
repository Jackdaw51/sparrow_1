library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_peak_finder is
end tb_peak_finder;

architecture Behavioral of tb_peak_finder is
    constant CLK_PERIOD : time := 10 ns;
    
    signal clk            : std_logic := '0';
    signal reset          : std_logic := '1';
    signal s_axis_tdata   : std_logic_vector(63 downto 0) := (others => '0');
    signal s_axis_tvalid  : std_logic := '0';
    signal s_axis_tlast   : std_logic := '0';
    signal peak_bin_index : std_logic_vector(12 downto 0);
    signal peak_ready     : std_logic;

begin
    UUT: entity work.peak_finder
        port map (
            clk => clk, reset => reset,
            s_axis_tdata => s_axis_tdata, s_axis_tvalid => s_axis_tvalid,
            s_axis_tlast => s_axis_tlast, peak_bin_index => peak_bin_index,
            peak_ready => peak_ready
        );

    clk_process: process
    begin
        clk <= '0'; wait for CLK_PERIOD/2;
        clk <= '1'; wait for CLK_PERIOD/2;
    end process;

    stim_process: process
    begin
        reset <= '1';
        wait for 50 ns;
        reset <= '0';
        wait for 50 ns;

        -- Simulate an 8192-point FFT output frame
        for i in 0 to 8191 loop
            s_axis_tvalid <= '1';
            
            -- Inject a massive peak at bin index 42
            if i = 42 then
                -- Real = 1000, Imag = 1000
                s_axis_tdata(63 downto 32) <= std_logic_vector(to_signed(1000, 32));
                s_axis_tdata(31 downto 0)  <= std_logic_vector(to_signed(1000, 32));
            else
                -- Noise / minor signals everywhere else
                s_axis_tdata(63 downto 32) <= std_logic_vector(to_signed(1, 32));
                s_axis_tdata(31 downto 0)  <= std_logic_vector(to_signed(1, 32));
            end if;
            
            if i = 8191 then
                s_axis_tlast <= '1';
            else
                s_axis_tlast <= '0';
            end if;
            
            wait for CLK_PERIOD;
        end loop;
        
        s_axis_tvalid <= '0';
        s_axis_tlast  <= '0';
        s_axis_tdata  <= (others => '0');
        
        wait;
    end process;
end Behavioral;