--
-- Written by Ryan Kim, Digilent Inc.
-- Modified by Michael Mattioli
--
-- Description: Demo for the OLED display. First displays the alphabet for ~4 seconds and then
-- clears the display, waits for a ~1 second and then displays "Hello world!".
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity oled_writer is
    port (
        clk_100 : in std_logic; -- System clock
        rst : in std_logic; -- Global synchronous reset
        en : in std_logic; -- Block enable pin
        data_in : in std_logic_vector (19 downto 0); -- Data input to be displayed on the OLED
        test_counter : in std_logic_vector (15 downto 0);
        sdout : out std_logic; -- SPI data out
        oled_sclk : out std_logic; -- SPI clock
        oled_dc : out std_logic; -- Data/Command controller
        fin : out std_logic); -- Finish flag for block
end oled_writer;

architecture behavioral of oled_writer is

    -- SPI controller
    component spi_ctrl
        port (
            clk_100 : in std_logic;
            rst : in std_logic;
            en : in std_logic;
            sdata : in std_logic_vector (7 downto 0);
            sdout : out std_logic;
            oled_sclk : out std_logic;
            fin : out std_logic);
    end component;

    -- delay controller
    component delay
        port (
            clk_100 : in std_logic;
            rst : in std_logic;
            delay_ms : in std_logic_vector (11 downto 0);
            delay_en : in std_logic;
            delay_fin : out std_logic);
    end component;

    -- character library, latency = 1
    component ascii_rom
        port (
            clk_100 : in std_logic; -- System clock
            addr : in std_logic_vector (10 downto 0); -- First 8 bits is the ASCII value of the character, the last 3 bits are the parts of the char
            dout : out std_logic_vector (7 downto 0)); -- Data byte out
    end component;

    -- States for state machine
    type states is (
        Idle,
        ClearDC,
        SetPage,
        PageNum,
        LeftColumn1,
        LeftColumn2,
        SetDC,
        Alphabet,
        Wait1,
        ClearScreen,
        Wait2,
        WriteScreen,
        Wait3,
        UpdateScreen,
        SendChar1,
        SendChar2,
        SendChar3,
        SendChar4,
        SendChar5,
        SendChar6,
        SendChar7,
        SendChar8,
        ReadMem,
        ReadMem2,
        Done,
        Transition1,
        Transition2,
        Transition3,
        Transition4,
        Transition5
    );

    type oled_mem is array (0 to 3, 0 to 15) of std_logic_vector (7 downto 0);

    -- Variable that contains what the screen will be after the next UpdateScreen state
    signal current_screen : oled_mem;

    -- Constant that contains the screen filled with the Alphabet and numbers
    constant alphabet_screen : oled_mem := ((x"41", x"42", x"43", x"44", x"45", x"46", x"47", x"48", x"49", x"4A", x"4B", x"4C", x"4D", x"4E", x"4F", x"50"),
    (x"51", x"52", x"53", x"54", x"55", x"56", x"57", x"58", x"59", x"5A", x"61", x"62", x"63", x"64", x"65", x"66"),
    (x"67", x"68", x"69", x"6A", x"6B", x"6C", x"6D", x"6E", x"6F", x"70", x"71", x"72", x"73", x"74", x"75", x"76"),
    (x"77", x"78", x"79", x"7A", x"30", x"31", x"32", x"33", x"34", x"35", x"36", x"37", x"38", x"39", x"7F", x"7F"));

    -- Constant that fills the screen with blank (spaces) entries
    constant clear_screen : oled_mem := ((x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20"),
    (x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20"),
    (x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20"),
    (x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20", x"20"));
    -- Variable that will be filled with the data to print
    signal data_screen : oled_mem := clear_screen;

    -- Current overall state of the state machine
    signal current_state : states := Idle;

    -- State to go to after the SPI transmission is finished
    signal after_state : states;

    -- State to go to after the set page sequence
    signal after_page_state : states;

    -- State to go to after sending the character sequence
    signal after_char_state : states;

    -- State to go to after the UpdateScreen is finished
    signal after_update_state : states;

    -- Contains the value to be outputted to oled_dc
    signal temp_dc : std_logic := '0';

    -- Used in the Delay controller block
    signal temp_delay_ms : std_logic_vector (11 downto 0); -- Amount of ms to delay
    signal temp_delay_en : std_logic := '0'; -- Enable signal for the Delay block
    signal temp_delay_fin : std_logic; -- Finish signal for the Delay block

    -- Used in the SPI controller block
    signal temp_spi_en : std_logic := '0'; -- Enable signal for the SPI block
    signal temp_sdata : std_logic_vector (7 downto 0) := (others => '0'); -- Data to be sent out on SPI
    signal temp_spi_fin : std_logic; -- Finish signal for the SPI block

    signal temp_char : std_logic_vector (7 downto 0) := (others => '0'); -- Contains ASCII value for character
    signal temp_addr : std_logic_vector (10 downto 0) := (others => '0'); -- Contains address to byte needed in memory
    signal temp_dout : std_logic_vector (7 downto 0); -- Contains byte outputted from memory
    signal temp_page : std_logic_vector (1 downto 0) := (others => '0'); -- Current page
    signal temp_index : integer range 0 to 15 := 0; -- Current character on page

    
    type note_record is record
        freq_max   : integer; 
        ascii_code : std_logic_vector(23 downto 0);
    end record;
    type note_array is array (0 to 99) of note_record;

    -- Pre-compiled Look-Up Table (LUT) [Note][Diesis/Space][Ottava]
    -- space = 0x20, '#' = 0x23, Numeri = 0x31-0x39
    constant NOTE_LUT : note_array := (
        ( 34, x"432031"),   -- C 1  
        ( 36, x"432331"),   -- C#1  
        ( 38, x"442031"),   -- D 1  
        ( 40, x"442331"),   -- D#1  
        ( 42, x"452031"),   -- E 1  
        ( 45, x"462031"),   -- F 1  
        ( 48, x"462331"),   -- F#1  
        ( 50, x"472031"),   -- G 1  
        ( 53, x"472331"),   -- G#1  
        ( 57, x"412031"),   -- A 1  
        ( 60, x"412331"),   -- A#1  
        ( 64, x"422031"),   -- B 1  
        ( 67, x"432032"),   -- C 2  
        ( 71, x"432332"),   -- C#2  
        ( 76, x"442032"),   -- D 2  
        ( 80, x"442332"),   -- D#2  
        ( 85, x"452032"),   -- E 2  (Start guitar extension, Low E ~82.4 Hz)
        ( 90, x"462032"),   -- F 2  
        ( 95, x"462332"),   -- F#2  
        ( 101, x"472032"),  -- G 2  
        ( 107, x"472332"),  -- G#2  
        ( 113, x"412032"),  -- A 2  
        ( 120, x"412332"),  -- A#2  
        ( 127, x"422032"),  -- B 2  
        ( 135, x"432033"),  -- C 3  
        ( 143, x"432333"),  -- C#3  
        ( 151, x"442033"),  -- D 3  
        ( 160, x"442333"),  -- D#3  
        ( 170, x"452033"),  -- E 3  
        ( 180, x"462033"),  -- F 3  
        ( 190, x"462333"),  -- F#3  
        ( 202, x"472033"),  -- G 3  
        ( 214, x"472333"),  -- G#3  
        ( 227, x"412033"),  -- A 3  
        ( 240, x"412333"),  -- A#3  
        ( 254, x"422033"),  -- B 3  
        ( 269, x"432034"),  -- C 4  (Middle C)
        ( 285, x"432334"),  -- C#4  
        ( 302, x"442034"),  -- D 4  
        ( 320, x"442334"),  -- D#4  
        ( 339, x"452034"),  -- E 4  
        ( 360, x"462034"),  -- F 4  
        ( 381, x"462334"),  -- F#4  
        ( 404, x"472034"),  -- G 4  
        ( 428, x"472334"),  -- G#4  
        ( 453, x"412034"),  -- A 4  (Central A 440 Hz)
        ( 480, x"412334"),  -- A#4  
        ( 509, x"422034"),  -- B 4  
        ( 539, x"432035"),  -- C 5  
        ( 571, x"432335"),  -- C#5  
        ( 605, x"442035"),  -- D 5  
        ( 641, x"442335"),  -- D#5  
        ( 679, x"452035"),  -- E 5  
        ( 719, x"462035"),  -- F 5  
        ( 762, x"462335"),  -- F#5  
        ( 807, x"472035"),  -- G 5  
        ( 855, x"472335"),  -- G#5  
        ( 906, x"412035"),  -- A 5  
        ( 960, x"412335"),  -- A#5  
        ( 1017, x"422035"), -- B 5  
        ( 1078, x"432036"), -- C 6  
        ( 1142, x"432336"), -- C#6  
        ( 1210, x"442036"), -- D 6  
        ( 1282, x"442336"), -- D#6  
        ( 1358, x"452036"), -- E 6  
        ( 1438, x"462036"), -- F 6  
        ( 1524, x"462336"), -- F#6  
        ( 1615, x"472036"), -- G 6  
        ( 1711, x"472336"), -- G#6  
        ( 1812, x"412036"), -- A 6  
        ( 1920, x"412336"), -- A#6  
        ( 2034, x"422036"), -- B 6  
        ( 2155, x"432037"), -- C 7  
        ( 2283, x"432337"), -- C#7  
        ( 2419, x"442037"), -- D 7  
        ( 2563, x"442337"), -- D#7  
        ( 2715, x"452037"), -- E 7  
        ( 2877, x"462037"), -- F 7  
        ( 3048, x"462337"), -- F#7  
        ( 3229, x"472037"), -- G 7  
        ( 3421, x"472337"), -- G#7  
        ( 3625, x"412037"), -- A 7  
        ( 3840, x"412337"), -- A#7  
        ( 4069, x"422037"), -- B 7  
        ( 4310, x"432038"), -- C 8  
        ( 4567, x"432338"), -- C#8  
        ( 4838, x"442038"), -- D 8  
        ( 5126, x"442338"), -- D#8  
        ( 5431, x"452038"), -- E 8  
        ( 5754, x"462038"), -- F 8  
        ( 6096, x"462338"), -- F#8  
        ( 6458, x"472038"), -- G 8  
        ( 6842, x"472338"), -- G#8  
        ( 7249, x"412038"), -- A 8  
        ( 7680, x"412338"), -- A#8  
        ( 8137, x"422038"), -- B 8  
        ( 8621, x"432039"), -- C 9  
        ( 9134, x"432339"), -- C#9  
        ( 9677, x"442039"), -- D 9  
        ( 9999, x"442339")  -- D#9  (Max value)
    );


    function note_finder(x : in std_logic_vector(15 downto 0)) return std_logic_vector is
        variable digit_thousands : integer;
        variable digit_hundreds  : integer;
        variable digit_tens      : integer;
        variable digit_ones      : integer;
        variable temp_freq : integer;
        variable ascii     : std_logic_vector(23 downto 0) := x"2D2D2D"; -- Default "---"
    begin
        digit_thousands := conv_integer(x(15 downto 12));
        digit_hundreds  := conv_integer(x(11 downto  8));
        digit_tens      := conv_integer(x(7  downto  4));
        digit_ones      := conv_integer(x(3  downto  0));
        temp_freq := (digit_thousands * 1000) + 
                     (digit_hundreds  * 100)  + 
                     (digit_tens      * 10)   + 
                     digit_ones;

        -- Check if frequency is lower than C1 or out of scale
        if temp_freq >= 30 and temp_freq <= 9999 then
            -- Search inside Look Up Table
            for i in 0 to NOTE_LUT'length - 1 loop -- The for cycle is 'fast' because the values are costants
                if temp_freq <= NOTE_LUT(i).freq_max then
                    ascii := NOTE_LUT(i).ascii_code;
                    exit; -- Interrompe il ciclo appena trova la nota corretta
                end if;
            end loop;
        end if;

        return ascii;
    end function note_finder;


    function to_ascii(x : in std_logic_vector(3 downto 0)) return std_logic_vector is
        variable ascii : std_logic_vector(7 downto 0);
    begin
        case x is
            when "0000" => ascii := x"30"; -- 0
            when "0001" => ascii := x"31"; -- 1
            when "0010" => ascii := x"32"; -- 2
            when "0011" => ascii := x"33"; -- 3
            when "0100" => ascii := x"34"; -- 4
            when "0101" => ascii := x"35"; -- 5
            when "0110" => ascii := x"36"; -- 6
            when "0111" => ascii := x"37"; -- 7
            when "1000" => ascii := x"38"; -- 8
            when "1001" => ascii := x"39"; -- 9
            when others => ascii := x"45"; -- E for error
        end case;
        return ascii;
    end function to_ascii;

begin

    oled_dc <= temp_dc;

    -- "Example" finish flag only high when in done state
    fin <= '1' when current_state = Done else
        '0';

    -- Instantiate SPI controller
    spi_comp : spi_ctrl port map(
        clk_100 => clk_100,
        rst => rst,
        en => temp_spi_en,
        sdata => temp_sdata,
        sdout => sdout,
        oled_sclk => oled_sclk,
        fin => temp_spi_fin);

    -- Instantiate delay
    delay_comp : delay port map(
        clk_100 => clk_100,
        rst => rst,
        delay_ms => temp_delay_ms,
        delay_en => temp_delay_en,
        delay_fin => temp_delay_fin);

    -- Instantiate ASCII character library
    char_lib_comp : ascii_rom port map(
        clk_100 => clk_100,
        addr => temp_addr,
        dout => temp_dout);

    process (clk_100)
    begin
        if rising_edge(clk_100) then
            case current_state is
                    -- Idle until en pulled high than intialize Page to 0 and go to state alphabet afterwards
                when Idle =>
                    if en = '1' then
                        current_state <= ClearDC;
                        after_page_state <= Alphabet;
                        temp_page <= "00";
                    end if;
                    -- Set current_screen to constant alphabet_screen and update the screen; go to state Wait1 afterwards
                when Alphabet =>
                    current_screen <= alphabet_screen;
                    after_update_state <= Wait1;
                    current_state <= UpdateScreen;
                    -- Wait 4ms and go to ClearScreen
                when Wait1 =>
                    temp_delay_ms <= "111110100000"; -- 4000
                    after_state <= ClearScreen;
                    current_state <= Transition3; -- Transition3 = delay transition states
                    -- Set current_screen to constant clear_screen and update the screen; go to state Wait2 afterwards
                when ClearScreen =>
                    current_screen <= clear_screen;
                    after_update_state <= Wait2;
                    current_state <= UpdateScreen;
                    -- Wait 1ms and go to WriteScreen
                when Wait2 =>
                    temp_delay_ms <= "001111101000"; -- 1000
                    after_state <= WriteScreen;
                    current_state <= Transition3; -- Transition3 = delay transition states
                    -- Keep printing the value of data to the screen
                when WriteScreen =>
                    current_screen <= data_screen;
                    after_update_state <= Wait3;
                    current_state <= UpdateScreen;
                when Wait3 =>
                    temp_delay_ms <= "001111101000"; -- 1ms
                    after_state <= WriteScreen; -- Keep writing
                    current_state <= Transition3;
                when Done =>
                    if en = '0' then
                        current_state <= Idle;
                    end if;

                    -- UpdateScreen State
                    -- 1. Gets ASCII value from current_screen at the current page and the current spot
                    --    of the page
                    -- 2. If on the last character of the page transition update the page number, if on
                    --    the last page(3) then the updateScreen go to "after_update_state" after
                when UpdateScreen =>
                    temp_char <= current_screen(conv_integer(temp_page), temp_index);
                    if temp_index = 15 then
                        temp_index <= 0;
                        temp_page <= temp_page + 1;
                        after_char_state <= ClearDC;
                        if temp_page = "11" then
                            after_page_state <= after_update_state;
                        else
                            after_page_state <= UpdateScreen;
                        end if;
                    else
                        temp_index <= temp_index + 1;
                        after_char_state <= UpdateScreen;
                    end if;
                    current_state <= SendChar1;

                    -- Update Page states
                    -- 1. Sets oled_dc to command mode
                    -- 2. Sends the SetPage Command
                    -- 3. Sends the Page to be set to
                    -- 4. Sets the start pixel to the left column
                    -- 5. Sets oled_dc to data mode
                when ClearDC =>
                    temp_dc <= '0';
                    current_state <= SetPage;
                when SetPage =>
                    temp_sdata <= "00100010";
                    after_state <= PageNum;
                    current_state <= Transition1;
                when PageNum =>
                    temp_sdata <= "000000" & temp_page;
                    after_state <= LeftColumn1;
                    current_state <= Transition1;
                when LeftColumn1 =>
                    temp_sdata <= "00000000";
                    after_state <= LeftColumn2;
                    current_state <= Transition1;
                when LeftColumn2 =>
                    temp_sdata <= "00010000";
                    after_state <= SetDC;
                    current_state <= Transition1;
                when SetDC =>
                    temp_dc <= '1';
                    current_state <= after_page_state;
                    -- End update Page states

                    -- Send character states
                    -- 1. Sets the address to ASCII value of character with the counter appended to the
                    --    end
                    -- 2. Waits a clock cycle for the data to get ready by going to ReadMem and ReadMem2
                    --    states
                    -- 3. Send the byte of data given by the ROM
                    -- 4. Repeat 7 more times for the rest of the character bytes
                when SendChar1 =>
                    temp_addr <= temp_char & "000";
                    after_state <= SendChar2;
                    current_state <= ReadMem;
                when SendChar2 =>
                    temp_addr <= temp_char & "001";
                    after_state <= SendChar3;
                    current_state <= ReadMem;
                when SendChar3 =>
                    temp_addr <= temp_char & "010";
                    after_state <= SendChar4;
                    current_state <= ReadMem;
                when SendChar4 =>
                    temp_addr <= temp_char & "011";
                    after_state <= SendChar5;
                    current_state <= ReadMem;
                when SendChar5 =>
                    temp_addr <= temp_char & "100";
                    after_state <= SendChar6;
                    current_state <= ReadMem;
                when SendChar6 =>
                    temp_addr <= temp_char & "101";
                    after_state <= SendChar7;
                    current_state <= ReadMem;
                when SendChar7 =>
                    temp_addr <= temp_char & "110";
                    after_state <= SendChar8;
                    current_state <= ReadMem;
                when SendChar8 =>
                    temp_addr <= temp_char & "111";
                    after_state <= after_char_state;
                    current_state <= ReadMem;
                when ReadMem =>
                    current_state <= ReadMem2;
                when ReadMem2 =>
                    temp_sdata <= temp_dout;
                    current_state <= Transition1;
                    -- End send character states

                    -- SPI transitions
                    -- 1. Set en to 1
                    -- 2. Waits for spi_ctrl to finish
                    -- 3. Goes to clear state (Transition5)
                when Transition1 =>
                    temp_spi_en <= '1';
                    current_state <= Transition2;
                when Transition2 =>
                    if temp_spi_fin = '1' then
                        current_state <= Transition5;
                    end if;
                    -- End SPI transitions

                    -- Delay transitions
                    -- 1. Set delay_en to 1
                    -- 2. Waits for delay to finish
                    -- 3. Goes to Clear state (Transition5)
                when Transition3 =>
                    temp_delay_en <= '1';
                    current_state <= Transition4;
                when Transition4 =>
                    if temp_delay_fin = '1' then
                        current_state <= Transition5;
                    end if;
                    -- End Delay transitions

                    -- Clear transition
                    -- 1. Sets both delay_en and en to 0
                    -- 2. Go to after state
                when Transition5 =>
                    temp_spi_en <= '0';
                    temp_delay_en <= '0';
                    current_state <= after_state;
                    -- End Clear transition

                when others =>
                    current_state <= Idle;
            end case;
        end if;
    end process;

    Data_converter : process (clk_100)
        variable temp_chars: std_logic_vector(23 downto 0);
    begin
        if rising_edge(clk_100) then
            if rst = '1' then
                data_screen <= clear_screen;
            else
                temp_chars := note_finder(data_in(19 downto 4));

                data_screen(0, 0) <= to_ascii(data_in(19 downto 16));
                data_screen(0, 1) <= to_ascii(data_in(15 downto 12));
                data_screen(0, 2) <= to_ascii(data_in(11 downto 8));
                data_screen(0, 3) <= to_ascii(data_in(7 downto 4));
                data_screen(0, 4) <= x"2E"; -- Decimal point
                data_screen(0, 5) <= to_ascii(data_in(3 downto 0));
                data_screen(0, 6) <= x"20"; -- space
                data_screen(0, 7) <= x"48"; -- H
                data_screen(0, 8) <= x"7A"; -- z
                data_screen(0, 9) <= x"20"; -- space
                data_screen(0, 10) <= x"2D"; -- -
                data_screen(0, 11) <= x"20"; -- space
                data_screen(0, 12) <= temp_chars(23 downto 16);
                data_screen(0, 13) <= temp_chars(15 downto 8);
                data_screen(0, 14) <= temp_chars(7 downto 0);

                data_screen(2, 0) <= to_ascii(test_counter(15 downto 12));
                data_screen(2, 1) <= to_ascii(test_counter(11 downto 8));
                data_screen(2, 2) <= to_ascii(test_counter(7 downto 4));
                data_screen(2, 3) <= to_ascii(test_counter(3 downto 0));
                data_screen(2, 3) <= x"73"; -- s
            end if;
        end if;
    end process;

end behavioral;