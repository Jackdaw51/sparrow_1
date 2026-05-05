library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

-- Stepper motor specification:
-- 4 phases
-- speed variation index: 1/64
-- voltage: 5V
-- frequency: 100Hz ?
-- step angle: 5.625° (1/64) ?
-- 4096 steps per revolution (360° / 5.625° * 64) half-step sequence
-- 2048 steps per revolution (360° / 5.625° * 32) full-step sequence

-- frequency = RPM * steps_per_revolution / 60
-- For 6 RPM (one every 10 seconds), frequency = 6 * 2048 / 60 = 204.8Hz
-- 488,281 cycles per step at 100MHz clock, 2^19 bits needed for counter
-- If resistance from guitar too high,
--start at 100Hz and accelerates to 204.8Hz in a few milliseconds

entity sm_control is
    port (
        clk_100 : in std_logic; --Clock
        reset : in std_logic; --Reset
        ce_204_8 : in std_logic; --Clock enable for 204.8Hz signal, used to time the steps

        rotation : in std_logic; -- If true rotate, 0 stop
        direction : in std_logic; -- 0 rotate clockwise, 1 rotate coutner-clockwise

        -- Signals controlling the stepper motor
        sm_c_1 : out std_logic;
        sm_c_2 : out std_logic;
        sm_c_3 : out std_logic;
        sm_c_4 : out std_logic;

        motor_ready : out std_logic -- Signal to indicate motor is ready for next command
    );
end entity sm_control;

architecture behavioral of sm_control is

    --Signal definition
    signal phase : std_logic_vector(7 downto 0) := "00000000"; -- 2-bit signal to control the motor phases
    signal active : std_logic := '0'; -- Indicate if motor was active
    -- Used to avoid backlash from guitar string tension
    signal stop_counter : integer range 0 to 614 := 0; -- Counter was originally 1023, idk if vivado accepts 614

begin
    State_machine : process (clk_100)
    begin
        if rising_edge(clk_100) then
            if reset = '1' then -- might need to change reset condition
                phase <= "00000000"; -- default phase;
                if active /= '1' then
                    active <= '0';
                    motor_ready <= '1';
                    -- Reset "active" only if it was not active, to avoid backlash
                    -- This is mainly executed on power-up
                end if;
            else
                if ce_204_8 = '1' then
                    -- Update the phase based on direction and rotation inputs
                    -- Only update the phase if rotation is active to avoid backlash
                    if rotation = '1' and direction = '0' then
                        active <= '1';
                        motor_ready <= '0';
                        stop_counter <= 0;
                        case phase is
                            when "00000000" => phase <= "00000001";
                            when "00000001" => phase <= "00000010";
                            when "00000010" => phase <= "00000100";
                            when "00000100" => phase <= "00001000";
                            when "00001000" => phase <= "00010000";
                            when "00010000" => phase <= "00100000";
                            when "00100000" => phase <= "01000000";
                            when "01000000" => phase <= "10000000";
                            when "10000000" => phase <= "00000001"; -- Loop back to the first phase
                            when others => phase <= phase; -- In case of error, stand still
                        end case;
                    elsif rotation = '1' and direction = '1' then
                        active <= '1';
                        motor_ready <= '0';
                        stop_counter <= 0;
                        case phase is
                            when "00000000" => phase <= "10000000";
                            when "10000000" => phase <= "01000000";
                            when "01000000" => phase <= "00100000";
                            when "00100000" => phase <= "00010000";
                            when "00010000" => phase <= "00001000";
                            when "00001000" => phase <= "00000100";
                            when "00000100" => phase <= "00000010";
                            when "00000010" => phase <= "00000001";
                            when "00000001" => phase <= "10000000";
                            when others => phase <= phase;
                        end case;
                    end if;
                end if;
            end if;

            if ce_204_8 = '1' then
                if rotation = '0' then
                    if active = '0' then
                        motor_ready <= '1'; -- If not active, immediately set motor_ready to true
                        -- Important at startup to avoid waiting for 3 seconds
                    else
                        if stop_counter < 614 then -- 3 seconds at 204.8Hz
                            stop_counter <= stop_counter + 1;
                        else
                            active <= '0'; -- After waiting, set active to false to turn off coils
                            phase <= "00000000";
                            stop_counter <= 0; -- Reset counter for next time
                            motor_ready <= '1';
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;
    -- We use full-step sequence instead of half-step sequence.
    -- This should give more torque, but less smooth movement. (Might need to switch)
    -- Full-step -> always two coils powered at same time;
    -- Half-step -> every other step, only one coil powered
    Movement : process (clk_100)
    begin
        if rising_edge(clk_100) then
            if ce_204_8 = '1' then
                if active = '1' then
                    case phase is
                        when "00000001" =>
                            sm_c_1 <= '1';
                            sm_c_2 <= '1';
                            sm_c_3 <= '0';
                            sm_c_4 <= '0';
                        when "00000010" =>
                            sm_c_1 <= '0';
                            sm_c_2 <= '1';
                            sm_c_3 <= '0';
                            sm_c_4 <= '0';
                        when "00000100" =>
                            sm_c_1 <= '0';
                            sm_c_2 <= '1';
                            sm_c_3 <= '1';
                            sm_c_4 <= '0';
                        when "00001000" =>
                            sm_c_1 <= '0';
                            sm_c_2 <= '0';
                            sm_c_3 <= '1';
                            sm_c_4 <= '0';
                        when "00010000" =>
                            sm_c_1 <= '0';
                            sm_c_2 <= '0';
                            sm_c_3 <= '1';
                            sm_c_4 <= '1';
                        when "00100000" =>
                            sm_c_1 <= '0';
                            sm_c_2 <= '0';
                            sm_c_3 <= '0';
                            sm_c_4 <= '1';
                        when "01000000" =>
                            sm_c_1 <= '1';
                            sm_c_2 <= '0';
                            sm_c_3 <= '0';
                            sm_c_4 <= '1';
                        when "10000000" =>
                            sm_c_1 <= '1';
                            sm_c_2 <= '0';
                            sm_c_3 <= '0';
                            sm_c_4 <= '0';
                        when others =>
                            sm_c_1 <= '0';
                            sm_c_2 <= '0';
                            sm_c_3 <= '0';
                            sm_c_4 <= '0';
                    end case;
                else -- If not active, turn off all coils to save power and avoid overheating
                    sm_c_1 <= '0';
                    sm_c_2 <= '0';
                    sm_c_3 <= '0';
                    sm_c_4 <= '0';
                end if;
            end if;

        end if;
    end process;

end architecture behavioral;