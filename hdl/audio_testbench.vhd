----------------------------------------------------------------------------------
-- Testbench for Audiointerface for Zedboard
--
-- Stefan Scholl, DC9ST
-- Microelectronic Systems Design Research Group
-- TU Kaiserslautern
-- 2014
----------------------------------------------------------------------------------
-- This testbench can operate in two different modes:
--
-- 1: sawtooth mode: outputs a simple sawtool signal on l and right headphone output (discards input signals)
-- 2: loopback mode: line in signals are routed to the headphone output 
--
-- choose between the two mode by commenting the code blocks below
--

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
        reset_btn : in std_logic; -- Connected to a push button (e.g., BTNC)

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

    component oled_ctrl
        port (
            clk : in std_logic;
            rst : in std_logic;
            raw_data : in std_logic_vector(31 downto 0); -- Data input to be displayed on the OLED
            oled_sdin : out std_logic;
            oled_sclk : out std_logic;
            oled_dc : out std_logic;
            oled_res : out std_logic;
            oled_vbat : out std_logic;
            oled_vdd : out std_logic);
    end component;

    signal clk_100_buffered : std_logic;

    signal counter : unsigned (5 downto 0);
    signal hphone_l, hphone_r : std_logic_vector (23 downto 0);
    signal hphone_valid : std_logic;
    signal new_sample : std_logic;
    signal sample_clk_48k : std_logic;
    signal line_in_l, line_in_r : std_logic_vector (23 downto 0);

    signal diapason_sample : std_logic_vector (23 downto 0);
    -- Signals for the 2-stage synchronizer
    signal sync_0, sync_1 : std_logic := '0';

    -- Counter for the 20ms delay (assuming 100MHz clock)
    signal debounce_counter : integer range 0 to 2_000_000 := 0;

    -- Internal register to hold the stable state
    signal stable_reset : std_logic := '0';
    signal clean_reset : std_logic := '0';

begin

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

    i_440hz : square_wave_440hz port map(
        clk => clk_100_buffered,
        ce_48k => new_sample,
        reset => clean_reset,
        audio_out => diapason_sample
    );

    i_oled : oled_ctrl port map(
        clk => clk_100,
        rst => clean_reset,
        raw_data => x"00038000",
        oled_sdin => oled_sdin,
        oled_sclk => oled_sclk,
        oled_dc => oled_dc,
        oled_res => oled_res,
        oled_vbat => oled_vbat,
        oled_vdd => oled_vdd
    );
    -- use comments to switch between TEST 1 (sawtooth) and 2 (loopback)

    --------------------------------------------------
    -- TEST 1: output sawtooth signal, discard input data
    -- process (clk_100)
    -- begin
    --     if (clk_100'event and clk_100 = '1') then

    --         hphone_valid <= '0';
    -- 		hphone_l <= (others => '0');
    -- 		hphone_r <= (others => '0');

    --         if new_sample = '1' then
    --             counter <= counter + 1;

    --             hphone_valid <= '1';
    --             hphone_l <= std_logic_vector(counter) & "000000000000000000" ;
    --             hphone_r <= std_logic_vector(counter) & "000000000000000000";
    --         end if;

    --     end if;
    -- end process;
    -- process (clk_100)
    -- begin
    --     if rising_edge(clk_100) then

    --         hphone_valid <= '0';
    --         hphone_l <= (others => '0');
    --         hphone_r <= (others => '0');

    --         if new_sample = '1' then

    --             hphone_valid <= '1';
    --             hphone_l <= diapason_sample;
    --             hphone_r <= diapason_sample;
    --         end if;

    --     end if;
    -- end process;

    -----------------------------------------------------
    -- TEST 2: loopback "line in" data to headphone output
    process (clk_100)
    begin
        if (clk_100'event and clk_100 = '1') then
            hphone_valid <= '0';
            hphone_l <= (others => '0');
            hphone_r <= (others => '0');

            if clean_reset = '0' and new_sample = '1' then

                hphone_valid <= '1';
                hphone_l <= line_in_r;
                hphone_r <= line_in_r;
            end if;
        end if;
    end process;

    --    process (clk_100)
    --    begin
    --        if (clk_100'event and clk_100 = '1') then

    --            hphone_valid <= '0';
    --            hphone_l <= (others => '0');
    --            hphone_r <= (others => '0');

    --            if new_sample = '1' then
    --                counter <= counter + 1;

    --                hphone_valid <= '1';
    --                hphone_l <= line_in_r;
    --                hphone_r <= line_in_r;
    --            end if;

    --        end if;
    --    end process;
    Reset_Debounce_Proc : process (clk_100)
    begin
        if rising_edge(clk_100) then

            -- Double-flop synchronizer to prevent metastability
            sync_0 <= reset_btn;
            sync_1 <= sync_0;

            -- Debounce logic
            if sync_1 /= stable_reset then
                -- The input differs from our stable state; start/continue counting
                if debounce_counter < 2_000_000 then
                    debounce_counter <= debounce_counter + 1;
                else
                    -- The signal has been stable for 20ms, update the state
                    stable_reset <= sync_1;
                    debounce_counter <= 0;
                end if;
            else
                -- The input matches the stable state (or is bouncing); reset the counter
                debounce_counter <= 0;
            end if;

        end if;
    end process;

    -- Assign the stable internal signal to your output
    clean_reset <= stable_reset;

    -- global clock buffer for the clock signal
    BUFG_inst : BUFG
    port map(
        O => clk_100_buffered, -- 1-bit output: Clock output
        I => clk_100 -- 1-bit input: Clock input
    );

end Behavioral;