library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_fft_ping_pong is
end tb_fft_ping_pong;

architecture Behavioral of tb_fft_ping_pong is
    constant CLK_PERIOD : time := 10 ns;
    
    signal clk           : std_logic := '0';
    signal reset         : std_logic := '1';
    signal din_data      : std_logic_vector(31 downto 0) := (others => '0');
    signal din_valid     : std_logic := '0';
    signal m_axis_tdata  : std_logic_vector(31 downto 0);
    signal m_axis_tvalid : std_logic;
    signal m_axis_tlast  : std_logic;
    signal m_axis_tready : std_logic := '0';

begin
    UUT: entity work.fft_ping_pong
        port map (
            clk => clk, reset => reset,
            din_data => din_data, din_valid => din_valid,
            m_axis_tdata => m_axis_tdata, m_axis_tvalid => m_axis_tvalid,
            m_axis_tlast => m_axis_tlast, m_axis_tready => m_axis_tready
        );

    clk_process: process
    begin
        clk <= '0'; wait for CLK_PERIOD/2;
        clk <= '1'; wait for CLK_PERIOD/2;
    end process;

    stim_process: process
    begin
        reset <= '1';
        wait for 100 ns;
        reset <= '0';
        wait for 100 ns;

        -- Write 8192 samples (fill one bank)
        for i in 0 to 8191 loop
            din_data <= std_logic_vector(to_unsigned(i, 32)); -- Send the index as data
            din_valid <= '1';
            wait for CLK_PERIOD;
            din_valid <= '0';
            wait for CLK_PERIOD * 2; -- Gap between writes (similar to integrate & dump)
        end loop;

        -- Observe Read Behavior
        -- At this point, the state machine should switch to FEED_FFT
        wait for CLK_PERIOD * 10;
        
        -- The FFT IP asserts tready when it can accept data
        m_axis_tready <= '1';
        
        -- Let it stream out the 8192 samples
        wait for CLK_PERIOD * 8500;
        
        m_axis_tready <= '0';
        wait;
    end process;
end Behavioral;