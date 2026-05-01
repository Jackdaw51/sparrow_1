library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity debouncer is
    generic (
        WAIT_CYCLES : integer := 2_000_000 -- 20ms at 100MHz
    );
    port (
        clk_100 : in std_logic;
        sig_in : in std_logic;
        sig_out : out std_logic
    );
end debouncer;

architecture Behavioral of debouncer is
    signal count : integer range 0 to WAIT_CYCLES := 0;
    signal state : std_logic := '0';
begin
    process (clk_100)
    begin
        if rising_edge(clk_100) then
            if sig_in /= state then
                if count < WAIT_CYCLES then
                    count <= count + 1;
                else
                    state <= sig_in;
                    count <= 0;
                end if;
            else
                count <= 0;
            end if;
        end if;
    end process;
    sig_out <= state;
end Behavioral;