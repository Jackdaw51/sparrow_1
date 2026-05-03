library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity smart_peak_finder is
    port (
        clk : in std_logic;
        reset : in std_logic;

        -- From FFT IP (m_axis_data)
        s_axis_tdata : in std_logic_vector(63 downto 0);
        s_axis_tvalid : in std_logic;
        s_axis_tlast : in std_logic;

        -- Final Result
        peak_bin_index : out std_logic_vector(12 downto 0);
        peak_ready : out std_logic
    );
end smart_peak_finder;

architecture Behavioral of smart_peak_finder is

    type state_type is (IDLE, SEARCH_PEAK, DONE);
    signal state : state_type := IDLE;

    -- Memory Array Types & Signals
    -- Only need to read first half
    type ram_full_t is array (0 to 4095) of unsigned(15 downto 0);
    type ram_half_t is array (0 to 2047) of unsigned(15 downto 0);
    type ram_third_t is array (0 to 1365) of unsigned(15 downto 0);

    signal bram1 : ram_full_t := (others => (others => '0'));
    signal bram2 : ram_half_t := (others => (others => '0'));
    signal bram3 : ram_third_t := (others => (others => '0'));

    attribute ram_style : string;
    attribute ram_style of bram1 : signal is "block";
    attribute ram_style of bram2 : signal is "block";
    attribute ram_style of bram3 : signal is "block";

    -- FFT Unpacking & Power Calculation Signals
    signal fft_valid : std_logic := '0';
    signal fft_bin_index : unsigned(12 downto 0) := (others => '0');
    signal real_part, imag_part : signed(31 downto 0);
    signal pwr_full : unsigned(63 downto 0);
    signal pwr_val_16 : unsigned(15 downto 0);

    -- Pointers and Counters
    signal mod3_counter : integer range 0 to 2 := 0;
    signal bram3_ptr : integer range 0 to 2730 := 0;
    signal search_index : unsigned(12 downto 0) := (others => '0');

    -- Pipeline Registers
    signal val1, val2_raw, val3_raw : unsigned(15 downto 0) := (others => '0');
    signal mult_stage_1 : unsigned(31 downto 0) := (others => '0');
    signal val3_delayed : unsigned(15 downto 0) := (others => '0');
    signal hps_power : unsigned(47 downto 0) := (others => '0');
    signal max_hps_pwr : unsigned(47 downto 0) := (others => '0');

    signal index_delay1, index_delay2, index_delay3 : unsigned(12 downto 0) := (others => '0');

    constant MAX_SEARCH_BIN : integer := 4095;

begin

    fft_valid <= s_axis_tvalid;
    real_part <= signed(s_axis_tdata(63 downto 32));
    imag_part <= signed(s_axis_tdata(31 downto 0));
    pwr_full <= unsigned(real_part * real_part) + unsigned(imag_part * imag_part);
    pwr_val_16 <= pwr_full(47 downto 32); -- Downsamples them to 16 bits to have a final 48 bits value

    process (clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state <= IDLE;
                peak_ready <= '0';
                peak_bin_index <= (others => '0');
                mod3_counter <= 0;
                bram3_ptr <= 0;
                fft_bin_index <= (others => '0');
                search_index <= (others => '0');
                max_hps_pwr <= (others => '0');
            else
                peak_ready <= '0';

                if fft_valid = '1' then
                    if s_axis_tlast = '1' then
                        fft_bin_index <= (others => '0');
                    else
                        fft_bin_index <= fft_bin_index + 1;
                    end if;
                end if;

                -- PORT A: write 
                if fft_valid = '1' then
                    if fft_bin_index < 4096 then
                        bram1(to_integer(fft_bin_index)) <= pwr_val_16;

                        if fft_bin_index(0) = '0' then
                            bram2(to_integer(fft_bin_index(12 downto 1))) <= pwr_val_16;
                        end if;

                        if mod3_counter = 2 then
                            bram3(bram3_ptr) <= pwr_val_16;
                            bram3_ptr <= bram3_ptr + 1;
                            mod3_counter <= 0;
                        else
                            mod3_counter <= mod3_counter + 1;
                        end if;
                    end if;

                    if s_axis_tlast = '1' then
                        bram3_ptr <= 0;
                        mod3_counter <= 0;
                    end if;
                end if;

                -- PORT B: read (State Machine)
                case state is

                    when IDLE =>
                        search_index <= (others => '0');
                        max_hps_pwr <= (others => '0');

                        if fft_valid = '1' and s_axis_tlast = '1' then
                            state <= SEARCH_PEAK;
                        end if;

                    when SEARCH_PEAK =>

                        -- CLOCK 0: Read from BRAMs Safely (1 Read Port per BRAM!)
                        if search_index <= MAX_SEARCH_BIN then
                            val1 <= bram1(to_integer(search_index));

                            -- Only read if within bounds, otherwise let it hold old data
                            if search_index < 2048 then
                                val2_raw <= bram2(to_integer(search_index));
                            end if;

                            if search_index < 1365 then
                                val3_raw <= bram3(to_integer(search_index));
                            end if;

                            search_index <= search_index + 1;
                        end if;

                        index_delay1 <= search_index;

                        -- CLOCK 1: Multiplier Stage 1
                        -- If we exceeded the harmonic limit, safely multiply by val1 
                        if index_delay1 < 2048 then
                            mult_stage_1 <= val1 * val2_raw;
                        else
                            mult_stage_1 <= val1 * val1;
                        end if;

                        if index_delay1 < 1365 then
                            val3_delayed <= val3_raw;
                        else
                            val3_delayed <= val1;
                        end if;

                        index_delay2 <= index_delay1;

                        -- CLOCK 2: Multiplier Stage 2
                        hps_power <= mult_stage_1 * val3_delayed;
                        index_delay3 <= index_delay2;

                        -- CLOCK 3: Compare and Save Peak 
                        if index_delay3 > 0 then
                            if hps_power > max_hps_pwr then
                                max_hps_pwr <= hps_power;
                                peak_bin_index <= std_logic_vector(index_delay3);
                            end if;
                        end if;

                        if index_delay3 = MAX_SEARCH_BIN then
                            state <= DONE;
                        end if;

                    when DONE =>
                        peak_ready <= '1';
                        state <= IDLE;

                end case;
            end if;
        end if;
    end process;
end Behavioral;