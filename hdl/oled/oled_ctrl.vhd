--
-- Written by Ryan Kim, Digilent Inc.
-- Modified by Michael Mattioli
--
-- Description: Top level controller that controls the OLED display.
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity oled_ctrl is
    port ( 
        clk_100     : in std_logic;
        rst         : in std_logic;
        raw_data    : in std_logic_vector(31 downto 0); -- Data input to be displayed on the OLED
        oled_sdin   : out std_logic;
        oled_sclk   : out std_logic;
        oled_dc     : out std_logic;
        oled_res    : out std_logic;
        oled_vbat   : out std_logic;
        oled_vdd    : out std_logic);
end oled_ctrl;

architecture behavioral of oled_ctrl is

    component oled_init is
        port ( 
            clk_100     : in std_logic;
            rst         : in std_logic;
            en          : in std_logic;
            sdout       : out std_logic;
            oled_sclk   : out std_logic;
            oled_dc     : out std_logic;
            oled_res    : out std_logic;
            oled_vbat   : out std_logic;
            oled_vdd    : out std_logic;
            fin         : out std_logic);
    end component;

    component oled_writer is
        port ( 
            clk_100     : in std_logic;
            rst         : in std_logic;
            en          : in std_logic;
            data_in    : in std_logic_vector ( 19 downto 0);
            sdout       : out std_logic;
            oled_sclk   : out std_logic;
            oled_dc     : out std_logic;
            fin         : out std_logic);
    end component;

    type states is (Idle, OledInitialize, OledWriter);

    signal current_state : states := Idle;

    signal init_en          : std_logic := '0';
    signal init_done        : std_logic;
    signal init_sdata       : std_logic;
    signal init_spi_clk     : std_logic;
    signal init_dc          : std_logic;

    signal writer_en       : std_logic := '0';
    signal writer_sdata    : std_logic;
    signal writer_spi_clk  : std_logic;
    signal writer_dc       : std_logic;
    signal writer_done     : std_logic;

    signal data_print       : std_logic_vector(19 downto 0) := (others => '0');
    signal int_data         : unsigned(15 downto 0);
    signal frac_data        : unsigned(15 downto 0);

begin

    Initialize: oled_init port map (
        clk_100 => clk_100,
        rst => rst,
        en => init_en,
        sdout => init_sdata,
        oled_sclk => init_spi_clk,
        oled_dc => init_dc,
        oled_res => oled_res,
        oled_vbat => oled_vbat,
        oled_vdd => oled_vdd,
        fin => init_done
    );

    Writer: oled_writer port map (
        clk_100 => clk_100,
        rst => rst,
        en => writer_en,
        data_in => data_print,
        sdout => writer_sdata,
        oled_sclk => writer_spi_clk,
        oled_dc => writer_dc,
        fin => writer_done
    );

    -- MUXes to indicate which outputs are routed out depending on which block is enabled
    oled_sdin <= init_sdata when current_state = OledInitialize else writer_sdata;
    oled_sclk <= init_spi_clk when current_state = OledInitialize else writer_spi_clk;
    oled_dc <= init_dc when current_state = OledInitialize else writer_dc;
    -- End output MUXes

    -- MUXes that enable blocks when in the proper states
    init_en <= '1' when current_state = OledInitialize else '0';
    writer_en <= '1' when current_state = OledWriter else '0';
    -- End enable MUXes

    int_data <= unsigned(raw_data(31 downto 16));
    frac_data <= unsigned(raw_data(15 downto 0));

    process (clk_100)
    begin
        if rising_edge(clk_100) then
            if rst = '1' then
                current_state <= Idle;
            else
                case current_state is
                    when Idle =>
                        current_state <= OledInitialize;
                    -- Go through the initialization sequence
                    when OledInitialize =>
                        if init_done = '1' then
                            current_state <= OledWriter;
                        end if;
                    -- Start printing numbers
                    when OledWriter =>
                        current_state <= OledWriter; -- Never stop printing
                    when others =>
                        current_state <= Idle;
                end case;
            end if;
        end if;
    end process;

    Num_converter: process(clk_100)
        variable frac_bcd : unsigned(3 downto 0); -- 1 int_bcd digit (4 bits)
        variable frac_mult : unsigned(19 downto 0); -- 16 bits + 4 bits for *10

        variable int_bcd : unsigned(15 downto 0); -- 4 int_bcd digits, 4 bits each
        variable temp : unsigned(15 downto 0); -- Temporary variable for shifting during

    begin
        if rising_edge(clk_100) then
            if rst = '1' then
                data_print <= (others => '0');
            else
                frac_mult := unsigned(frac_data) * 10;
                frac_bcd := frac_mult(19 downto 16); -- Get the first decimal place

                int_bcd := (others => '0');
                temp := int_data;

                for i in 0 to 15 loop
                    -- 1. Check each int_bcd nibble. If > 4, add 3.
                    -- Thousands
                    if int_bcd(15 downto 12) > 4 then
                        int_bcd(15 downto 12) := int_bcd(15 downto 12) + 3;
                    end if;
                    -- Hundreds
                    if int_bcd(11 downto 8) > 4 then
                        int_bcd(11 downto 8) := int_bcd(11 downto 8) + 3;
                    end if;
                    -- Tens
                    if int_bcd(7 downto 4) > 4 then
                        int_bcd(7 downto 4) := int_bcd(7 downto 4) + 3;
                    end if;
                    -- Ones
                    if int_bcd(3 downto 0) > 4 then
                        int_bcd(3 downto 0) := int_bcd(3 downto 0) + 3;
                    end if;

                    -- 2. Shift the entire int_bcd register and Temp register left by 1
                    int_bcd := int_bcd(14 downto 0) & temp(15);
                    temp := temp(14 downto 0) & '0';
                end loop;

                data_print <= std_logic_vector(int_bcd) & std_logic_vector(frac_bcd);
            end if;
        end if;
    end process;

end behavioral;
