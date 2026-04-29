library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity integrate_and_dump is
    port (
        clk : in std_logic; -- Main system clock (e.g., 100 MHz)
        reset : in std_logic; -- Active high reset

        -- Input from audio codec (48 kHz sample rate)
        data_in : in std_logic_vector(23 downto 0);
        valid_in : in std_logic;

        -- Output to Ping-Pong buffer (4.8 kHz sample rate)
        data_out : out std_logic_vector(31 downto 0);
        valid_out : out std_logic
    );
end integrate_and_dump;

architecture Behavioral of integrate_and_dump is

    -- 28-bit accumulator to prevent overflow when adding ten 24-bit numbers
    signal accumulator : signed(27 downto 0);

    -- Counter to track the 10 samples
    signal count : integer range 0 to 9;

begin

    process (clk)
        variable input_ext : signed(27 downto 0);
    begin
        if rising_edge(clk) then
            if reset = '1' then
                accumulator <= (others => '0');
                count <= 0;
                data_out <= (others => '0');
                valid_out <= '0';
            else
                -- Default: clear the valid flag so it only pulses for 1 clock cycle
                valid_out <= '0';

                if valid_in = '1' then

                    -- Sign-extend the 24-bit input to 28 bits for safe addition
                    input_ext := resize(signed(data_in), 28);

                    if count = 9 then
                        -- We resize the 28-bit sum to 32 bits to properly sign-extend 
                        data_out <= std_logic_vector(resize(accumulator + input_ext, 32));
                        valid_out <= '1';

                        -- Reset accumulator and counter for the next batch
                        accumulator <= (others => '0');
                        count <= 0;
                    else
                        accumulator <= accumulator + input_ext;
                        count <= count + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

end Behavioral;