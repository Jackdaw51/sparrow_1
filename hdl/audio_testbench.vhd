library IEEE;
use IEEE.STD_LOGIC_1164.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.all;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
library UNISIM;
use UNISIM.VComponents.all;

entity audio_testbench is
    port (
        clk_100 : in std_logic; -- 100 mhz master takt

        sw_in : std_logic_vector(7 downto 0);
        btn_in : std_logic_vector(4 downto 0);
        led_out : out std_logic_vector(7 downto 0);

        AC_ADR0 : out std_logic; -- control signals to ADAU chip
        AC_ADR1 : out std_logic;
        AC_GPIO0 : out std_logic; -- I2S MISO
        AC_GPIO1 : in std_logic; -- I2S MOSI
        AC_GPIO2 : in std_logic; -- I2S_bclk
        AC_GPIO3 : in std_logic; -- I2S_LR
        AC_MCLK : out std_logic;
        AC_SCK : out std_logic;
        AC_SDA : inout std_logic;
        oled_sdin : out std_logic;
        oled_sclk : out std_logic;
        oled_dc : out std_logic;
        oled_res : out std_logic;
        oled_vbat : out std_logic;
        oled_vdd : out std_logic
    );
end audio_testbench;

architecture Behavioral of audio_testbench is
    component audio_top
        port (
            clk_100 : in std_logic; -- 100 mhz input clock 
            AC_ADR0 : out std_logic; -- contol signals to audio chip
            AC_ADR1 : out std_logic;
            AC_GPIO0 : out std_logic; -- I2S MISO
            AC_GPIO1 : in std_logic; -- I2S MOSI
            AC_GPIO2 : in std_logic; -- I2S_bclk
            AC_GPIO3 : in std_logic; -- I2S_LR
            AC_MCLK : out std_logic;
            AC_SCK : out std_logic;
            AC_SDA : inout std_logic;

            hphone_l : in std_logic_vector(23 downto 0);
            hphone_l_valid : in std_logic;
            hphone_r : in std_logic_vector(23 downto 0);
            hphone_r_valid_dummy : in std_logic;

            line_in_l : out std_logic_vector(23 downto 0);
            line_in_r : out std_logic_vector(23 downto 0);

            new_sample : out std_logic; -- goes up for 1 clk cycle if new sample is transmitted received
            sample_clk_48k : out std_logic -- sample clock 

        );
    end component;

    component square_wave_440hz
        port (
            clk : in std_logic;
            ce_48k : in std_logic;
            reset : in std_logic;
            audio_out : out std_logic_vector (23 downto 0)
        );
    end component;

    component button_manager
        port (
            clk_100_buffered : in std_logic; --Clock
            buttons_in  : in  std_logic_vector(4 downto 0);
            buttons_deb : out std_logic_vector(4 downto 0)
        );
    end component;

    component switch_manager
        port (
            clk_100_buffered : in std_logic; --Clock
            switches_in  : in  std_logic_vector(7 downto 0);
            switches_deb : out std_logic_vector(7 downto 0);
            switches_valid : out std_logic
        );
    end component;

    component sine_wave_440hz
        port (
            clk : in std_logic;
            ce_48k : in std_logic;
            reset : in std_logic;
            audio_out : out std_logic_vector (23 downto 0)
        );
    end component;

    component oled_ctrl
        port (
            clk_100 : in std_logic;
            rst : in std_logic;
            raw_data : in std_logic_vector(31 downto 0); -- Data input to be displayed on the OLED
            oled_sdin : out std_logic;
            oled_sclk : out std_logic;
            oled_dc : out std_logic;
            oled_res : out std_logic;
            oled_vbat : out std_logic;
            oled_vdd : out std_logic);
    end component;

    component sm_control
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
    end component;
    signal clk_100_buffered : std_logic;

    signal counter : unsigned (5 downto 0);
    signal hphone_l, hphone_r : std_logic_vector (23 downto 0);
    signal hphone_valid : std_logic;
    signal new_sample : std_logic;
    signal sample_clk_48k : std_logic;
    signal line_in_l, line_in_r : std_logic_vector (23 downto 0);

    signal diapason_sample : std_logic_vector (23 downto 0);

    -- Buttons and switches
    signal btn_deb : std_logic_vector(4 downto 0);
    signal sw_deb : std_logic_vector(7 downto 0);
    alias reset_btn_deb : std_logic is btn_deb(0);
    alias up_btn_deb : std_logic is btn_deb(1);
    alias down_btn_deb : std_logic is btn_deb(2);
    alias left_btn_deb : std_logic is btn_deb(3);
    alias right_btn_deb : std_logic is btn_deb(4);

    -- Internal register to hold the stable state
    signal clean_reset : std_logic := '0';

    signal sample_acc : unsigned(15 downto 0) := (others => '0');
    signal en_204_8Hz : std_logic := '0';

    -- Increment value: (204.8 / 48000) * 2^16 = 279.62... (round to 280)
    constant STEP_204_8 : unsigned(15 downto 0) := to_unsigned(280, 16);

    signal raw_data : std_logic_vector(31 downto 0) := (others => '0');

begin

    sine_wave_proc : process (clk_100_buffered)
    begin
        if rising_edge(clk_100_buffered) then

            hphone_valid <= '0';
            hphone_l <= (others => '0');
            hphone_r <= (others => '0');

            if clean_reset = '0' and new_sample = '1' then
                hphone_valid <= '1';
                hphone_l <= diapason_sample;
                hphone_r <= diapason_sample;
            end if;

        end if;
    end process;

    -----------------------------------------------------
    -- TEST 2: loopback "line in" data to headphone output
    -- loopback_proc : process (clk_100_buffered)
    -- begin
    --     if (clk_100_buffered'event and clk_100_buffered = '1') then
    --         hphone_valid <= '0';
    --         hphone_l <= (others => '0');
    --         hphone_r <= (others => '0');

    --         if clean_reset = '0' and new_sample = '1' then

    --             hphone_valid <= '1';
    --             hphone_l <= line_in_r;
    --             hphone_r <= line_in_r;
    --         end if;
    --     end if;
    -- end process;

    
    raw_data_proc : process (clk_100_buffered)
        variable counter : integer range 0 to 48000 := 48000;
        variable second_counter : integer range 0 to 999999 := 0;
    begin
        if rising_edge(clk_100_buffered) then
            if clean_reset = '1' then
                raw_data <= (others => '0');
                counter := 48000;
                second_counter := 0;
            elsif new_sample = '1' then
                counter := counter - 1;
                if counter = 0 then
                    raw_data <= std_logic_vector(to_unsigned(second_counter,16) & x"0000");
                    counter := 48000;
                    second_counter := second_counter + 1;
                end if;
            end if;
        end if;
    end process;

    sm_clock_proc : process (clk_100_buffered)
    begin
        if rising_edge(clk_100_buffered) then
            if clean_reset = '1' then
                sample_acc <= (others => '0');
                en_204_8Hz <= '0';
                -- Reset any other internal registers here
            else
                en_204_8Hz <= '0';
                if new_sample = '1' then
                    -- Every time a 48kHz sample arrives, we update the accumulator
                    sample_acc <= sample_acc + STEP_204_8;

                    -- Detect the rollover/overflow to create the 204.8Hz pulse
                    if sample_acc < STEP_204_8 then
                        en_204_8Hz <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Assign the stable internal signal to output
    clean_reset <= reset_btn_deb;
    led_out <= sw_deb;

    i_audio : audio_top port map(
        clk_100 => clk_100_buffered,
        AC_ADR0 => AC_ADR0,
        AC_ADR1 => AC_ADR1,
        AC_GPIO0 => AC_GPIO0,
        AC_GPIO1 => AC_GPIO1,
        AC_GPIO2 => AC_GPIO2,
        AC_GPIO3 => AC_GPIO3,
        AC_MCLK => AC_MCLK,
        AC_SCK => AC_SCK,
        AC_SDA => AC_SDA,

        hphone_l => hphone_l,
        hphone_l_valid => hphone_valid,
        hphone_r => hphone_r,
        hphone_r_valid_dummy => hphone_valid, --  this valid will be discarded later

        line_in_l => line_in_l,
        line_in_r => line_in_r,

        new_sample => new_sample,
        sample_clk_48k => sample_clk_48k

    );

    i_440hz : sine_wave_440hz port map(
        clk => clk_100_buffered,
        ce_48k => new_sample,
        reset => clean_reset,
        audio_out => diapason_sample
    );

    btn_man : button_manager port map(
        clk_100_buffered => clk_100_buffered,
        buttons_in => btn_in,
        buttons_deb => btn_deb
    );

    sw_man : switch_manager port map(
        clk_100_buffered => clk_100_buffered,
        switches_in => sw_in,
        switches_deb => sw_deb,
        switches_valid => open
    );

    i_oled : oled_ctrl port map(
        clk_100 => clk_100_buffered,
        rst => clean_reset,
        raw_data => raw_data,
        oled_sdin => oled_sdin,
        oled_sclk => oled_sclk,
        oled_dc => oled_dc,
        oled_res => oled_res,
        oled_vbat => oled_vbat,
        oled_vdd => oled_vdd
    );

    i_motor : sm_control port map(
        clk_100 => clk_100_buffered, --Clock
        reset => clean_reset, --Reset
        ce_204_8 => en_204_8Hz, --Clock enable for 204.8Hz signal, used to time the steps

        rotation => '0', -- If true rotate, 0 stop
        direction => '0', -- 0 rotate clockwise, 1 rotate coutner-clockwise

        -- Signals controlling the stepper motor
        sm_c_1 => open,
        sm_c_2 => open,
        sm_c_3 => open,
        sm_c_4 => open,

        motor_ready => open -- Signal to indicate motor is ready for next command
    );

    -- global clock buffer for the clock signal
    BUFG_inst : BUFG port map(
        O => clk_100_buffered, -- 1-bit output: Clock output
        I => clk_100 -- 1-bit input: Clock input
    );

end Behavioral;