library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_integrate_and_dump is
end tb_integrate_and_dump;

architecture Behavioral of tb_integrate_and_dump is
    constant CLK_PERIOD : time := 10 ns;
    
    signal clk       : std_logic := '0';
    signal reset     : std_logic := '1';
    signal data_in   : std_logic_vector(23 downto 0) := (others => '0');
    signal valid_in  : std_logic := '0';
    signal data_out  : std_logic_vector(31 downto 0);
    signal valid_out : std_logic;

begin
    UUT: entity work.integrate_and_dump
        port map (
            clk => clk, reset => reset,
            data_in => data_in, valid_in => valid_in,
            data_out => data_out, valid_out => valid_out
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

        -- Send 10 samples of value "100"
        for i in 1 to 10 loop
            data_in <= std_logic_vector(to_signed(100, 24));
            valid_in <= '1';
            wait for CLK_PERIOD;
            valid_in <= '0';
            wait for CLK_PERIOD * 4; -- Simulate gap between samples
        end loop;
        
        -- Send a few more to see if it resets correctly for the next batch
        for i in 1 to 3 loop
            data_in <= std_logic_vector(to_signed(50, 24));
            valid_in <= '1';
            wait for CLK_PERIOD;
            valid_in <= '0';
            wait for CLK_PERIOD * 4;
        end loop;

        wait;
    end process;
end Behavioral;