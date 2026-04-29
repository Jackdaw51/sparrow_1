--
-- Written by Ryan Kim, Digilent Inc.
-- Modified by Michael Mattioli
--
-- Description: Top level controller that controls the OLED display.
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity oled_ctrl is
    port (  clk         : in std_logic;
            rst         : in std_logic;
            data        : in real; -- Data input to be displayed on the OLED
            oled_sdin   : out std_logic;
            oled_sclk   : out std_logic;
            oled_dc     : out std_logic;
            oled_res    : out std_logic;
            oled_vbat   : out std_logic;
            oled_vdd    : out std_logic);
end oled_ctrl;

architecture behavioral of oled_ctrl is

    component oled_init is
        port (  clk         : in std_logic;
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
        port (  clk         : in std_logic;
                rst         : in std_logic;
                en          : in std_logic;
                data_int    : in std_logic_vector ( 19 downto 0);
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

    signal example_en       : std_logic := '0';
    signal example_sdata    : std_logic;
    signal example_spi_clk  : std_logic;
    signal example_dc       : std_logic;
    signal example_done     : std_logic;

    signal data_print       : std_logic_vector(19 downto 0) := (others => '0');

begin

    Initialize: oled_init port map (clk,
                                    rst,
                                    init_en,
                                    init_sdata,
                                    init_spi_clk,
                                    init_dc,
                                    oled_res,
                                    oled_vbat,
                                    oled_vdd,
                                    init_done);

    Writer: oled_writer port map ( clk,
                                rst,
                                writer_en,
                                data_print,
                                writer_sdata,
                                writer_spi_clk,
                                writer_dc,
                                example_done);

    -- MUXes to indicate which outputs are routed out depending on which block is enabled
    oled_sdin <= init_sdata when current_state = OledInitialize else writer_sdata;
    oled_sclk <= init_spi_clk when current_state = OledInitialize else writer_spi_clk;
    oled_dc <= init_dc when current_state = OledInitialize else writer_dc;
    -- End output MUXes

    -- MUXes that enable blocks when in the proper states
    init_en <= '1' when current_state = OledInitialize else '0';
    writer_en <= '1' when current_state = OledWriter else '0';
    -- End enable MUXes

    process (clk)
    begin
        if rising_edge(clk) then
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

    Num_converter: process(clk)
        signal data_0 : std_logic_vector(3 downto 0);
        signal data_1 : std_logic_vector(3 downto 0);
        signal data_2 : std_logic_vector(3 downto 0);
        signal data_3 : std_logic_vector(3 downto 0);
        signal data_4 : std_logic_vector(3 downto 0);
        signal data_tmp : real;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                data_print <= (others => '0');
            else
                data_tmp <= data * 10.0; -- Original data should be in format iiii.d
                data_0 <= std_logic_vector(to_unsigned(integer(data_tmp) mod 10, 4));
                data_1 <= std_logic_vector(to_unsigned((integer(data_tmp) / 10) mod 10, 4));
                data_2 <= std_logic_vector(to_unsigned((integer(data_tmp) / 100) mod 10, 4));
                data_3 <= std_logic_vector(to_unsigned((integer(data_tmp) / 1000) mod 10, 4));
                data_4 <= std_logic_vector(to_unsigned((integer(data_tmp) / 10000) mod 10, 4));

                data_print <= data_0 & data_1 & data_2 & data_3 & data_4;
            end if;
        end if;
    end process;

end behavioral;
