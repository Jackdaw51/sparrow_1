library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity nema17_control is
    port (
        clk : in std_logic; -- 100MHz clock input
        reset : in std_logic;
        -- Control Inputs
        rot_in : in std_logic; -- '1' to rotate, '0' to stop
        dir_in : in std_logic; -- '0' clockwise, '1' counter-clockwise
        speed_sel : in std_logic; -- '0' for fast, '1' for fine tuning
        -- Driver Outputs
        step_out : out std_logic; -- Step pulse
        dir_out : out std_logic;
        en_out : out std_logic -- Active Low
    );
end nema17_control;

architecture Behavioral of nema17_control is
    signal counter : unsigned(31 downto 0) := (others => '0');
    signal step_reg : std_logic := '0';
    signal limit_val : integer := 100_000; -- Default speed

begin

    -- Set Speed: Lower limit_val = Faster pulses
    -- limit_val = f_clocl / (2 * f_step), where f_step is desired frequency of step pulses
    -- f_step = 100Hz for fast tuning, 25Hz for fine tuning
    limit_val <= 750_000 when speed_sel = '1' else 2_000_000;
    
    process (clk)
    begin
        if reset = '1' then
            counter <= (others => '0');
            step_reg <= '0';
            en_out <= '1'; -- Disable motor on reset
        elsif rising_edge(clk) then
            if rot_in = '1' then
                en_out <= '0'; -- Enable motor (Active Low)
                dir_out <= dir_in; -- Set direction based on dir_in

                if counter >= limit_val then
                    step_reg <= not step_reg; -- Create the pulse (Driver cares about edges)
                    counter <= (others => '0');
                else
                    counter <= counter + 1;
                end if;
            else
                en_out <= '1'; -- Power down motor when not in use
                step_reg <= '0';
                counter <= (others => '0');
            end if;
        end if;
    end process;

    step_out <= step_reg;

end Behavioral;