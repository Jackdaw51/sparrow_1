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
    signal fft_bin_index : unsigned(12 downto 0) := (others => '0');
    signal real_part, imag_part : signed(31 downto 0) := (others => '0');
    signal real_sq, imag_sq : signed(63 downto 0) := (others => '0');
    signal pwr_full : unsigned(63 downto 0) := (others => '0');
    signal pwr_val_16 : unsigned(15 downto 0) := (others => '0');

    -- Delay Line (Conveyor Belt) Signals for Pipelining
    signal valid_delay : std_logic_vector(3 downto 0) := (others => '0');
    signal last_delay : std_logic_vector(3 downto 0) := (others => '0');
    type index_pipe_t is array (0 to 3) of unsigned(12 downto 0);
    signal index_delay : index_pipe_t := (others => (others => '0'));

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
    constant NOISE_THRESHOLD : unsigned(47 downto 0) := to_unsigned(32768, 48);
    -- Lower it

    -- 4 stage pipeline for writing, 3 stage pipeline for hps

begin

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

                -- Resetting Pipeline Registers
                valid_delay <= (others => '0');
                last_delay <= (others => '0');
                index_delay <= (others => (others => '0'));
                real_part <= (others => '0');
                imag_part <= (others => '0');
                real_sq <= (others => '0');
                imag_sq <= (others => '0');
                pwr_full <= (others => '0');
                pwr_val_16 <= (others => '0');
            else
                peak_ready <= '0';

                -- track index
                if s_axis_tvalid = '1' then
                    if s_axis_tlast = '1' then
                        fft_bin_index <= (others => '0');
                    else
                        fft_bin_index <= fft_bin_index + 1;
                    end if;
                end if;

                -- Shift Registers for Control Signals
                valid_delay <= valid_delay(2 downto 0) & s_axis_tvalid;
                last_delay <= last_delay(2 downto 0) & s_axis_tlast;
                index_delay(0) <= fft_bin_index;
                index_delay(1) <= index_delay(0);
                index_delay(2) <= index_delay(1);
                index_delay(3) <= index_delay(2);

                -- math pipeline
                -- Stage 1: Unpack
                real_part <= signed(s_axis_tdata(63 downto 32));
                imag_part <= signed(s_axis_tdata(31 downto 0));

                -- Stage 2: Multiply
                real_sq <= real_part * real_part;
                imag_sq <= imag_part * imag_part;

                -- Stage 3: Add
                pwr_full <= unsigned(real_sq) + unsigned(imag_sq);

                -- Downsamples them to 16 bits to have a final 48 bits value
                -- Stage 4: Truncate with SATURATION (Ceiling) and FLOOR
                if pwr_full(63 downto 48) /= x"0000" then
                    -- CEILING: The signal is massive. Max it out to prevent wrapping.
                    pwr_val_16 <= x"FFFF";
                elsif pwr_full > 0 and pwr_full(47 downto 32) = x"0000" then
                    -- FLOOR: weak signal, but not zero. Force to 1 so HPS doesn't multiply by zero.
                    pwr_val_16 <= x"0001";
                else
                    -- NORMAL: Signal perfectly fits in the middle bits.
                    pwr_val_16 <= pwr_full(47 downto 32);
                end if;

                -- PORT A: write 
                -- We now use the delayed signals that perfectly match pwr_val_16
                if valid_delay(3) = '1' then
                    if index_delay(3) < 4096 then
                        bram1(to_integer(index_delay(3))) <= pwr_val_16;

                        if index_delay(3)(0) = '0' then
                            bram2(to_integer(index_delay(3)(12 downto 1))) <= pwr_val_16;
                        end if;

                        if mod3_counter = 2 then
                            bram3(bram3_ptr) <= pwr_val_16;
                            bram3_ptr <= bram3_ptr + 1;
                            mod3_counter <= 0;
                        else
                            mod3_counter <= mod3_counter + 1;
                        end if;
                    end if;

                    if last_delay(3) = '1' then
                        bram3_ptr <= 0;
                        mod3_counter <= 0;
                    end if;
                end if;

                -- PORT B: read (State Machine)
                case state is

                    when IDLE =>
                        search_index <= (others => '0');
                        -- THE NOISE GATE: Require a minimum power to register a note
                        max_hps_pwr <= NOISE_THRESHOLD;

                        -- SILENCE DEFAULT: Clear the old note, if no bin beats the threshold, it stays 0.
                        peak_bin_index <= (others => '0');

                        index_delay1 <= (others => '0');
                        index_delay2 <= (others => '0');
                        index_delay3 <= (others => '0');

                        -- Wait for the delayed last signal so BRAM writes are completely finished
                        if valid_delay(3) = '1' and last_delay(3) = '1' then
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