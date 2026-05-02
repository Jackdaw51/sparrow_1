library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity fft_top is
    port (
        clk : in std_logic; -- 100 MHz System Clock
        reset : in std_logic; -- Active High Reset

        -- Physical Interface (from Audio Codec)
        adc_data_in : in std_logic_vector(23 downto 0);
        adc_valid_in : in std_logic;

        -- Final Output (To your OLED or Logic Analyzer)
        peak_freq_hz : out std_logic_vector(15 downto 0);
        peak_ready : out std_logic;

        peak_freq_tenths : out std_logic_vector(3 downto 0) -- A neat 0-9 digit for the OLED
    );
end fft_top;

architecture Structural of fft_top is

    -- 1. Integrate & Dump Signals (4.8 kHz)
    signal ds_data : std_logic_vector(31 downto 0);
    signal ds_valid : std_logic;

    -- 2. Ping-Pong / BRAM Signals
    signal axis_tdata : std_logic_vector(31 downto 0);
    signal axis_tvalid : std_logic;
    signal axis_tlast : std_logic;
    signal axis_tready : std_logic;

    -- 3. FFT Configuration & Internal Routing
    signal s_axis_config_tdata : std_logic_vector(15 downto 0) := x"5555";
    signal s_axis_config_tvalid : std_logic := '1';

    signal config_tready : std_logic;
    signal config_done : std_logic := '0';

    -- Add this new signal to pad your audio with a zeroed imaginary part
    signal complex_axis_tdata : std_logic_vector(63 downto 0);

    signal fft_data_internal : std_logic_vector(63 downto 0);
    signal fft_valid_internal : std_logic;
    signal fft_last_internal : std_logic;

    -- 4. Peak Finder Output Signals
    signal peak_bin_index : std_logic_vector(12 downto 0);
    signal internal_ready : std_logic;

    -- 5. Frequency Math Signals
    -- 13-bit index * 16-bit constant = 29-bit result
    signal freq_scaled : unsigned(28 downto 0);

    signal aresetn : std_logic;

    signal tenths_calc : unsigned(19 downto 0);

    -- Component Declarations
    component integrate_and_dump
        port (
            clk : in std_logic;
            reset : in std_logic;
            data_in : in std_logic_vector(23 downto 0);
            valid_in : in std_logic;
            data_out : out std_logic_vector(31 downto 0);
            valid_out : out std_logic
        );
    end component;

    component fft_ping_pong
        port (
            clk : in std_logic;
            reset : in std_logic;
            din_data : in std_logic_vector(31 downto 0);
            din_valid : in std_logic;
            m_axis_tdata : out std_logic_vector(31 downto 0);
            m_axis_tvalid : out std_logic;
            m_axis_tlast : out std_logic;
            m_axis_tready : in std_logic
        );
    end component;

    component xfft_0
        port (
            aclk : in std_logic;
            aresetn : in std_logic;
            s_axis_config_tdata : in std_logic_vector(15 downto 0);
            s_axis_config_tvalid : in std_logic;
            s_axis_config_tready : out std_logic;
            s_axis_data_tdata : in std_logic_vector(63 downto 0);
            s_axis_data_tvalid : in std_logic;
            s_axis_data_tready : out std_logic;
            s_axis_data_tlast : in std_logic;
            m_axis_data_tdata : out std_logic_vector(63 downto 0);
            m_axis_data_tvalid : out std_logic;
            m_axis_data_tlast : out std_logic;
            m_axis_data_tready : in std_logic;
            event_frame_started : out std_logic
        );
    end component;

    -- component peak_finder
    component smart_peak_finder
        port (
            clk : in std_logic;
            reset : in std_logic;
            s_axis_tdata : in std_logic_vector(63 downto 0);
            s_axis_tvalid : in std_logic;
            s_axis_tlast : in std_logic;
            peak_bin_index : out std_logic_vector(12 downto 0);
            peak_ready : out std_logic
        );
    end component;

begin

    -- Instance 1: Downsampler (48kHz -> 4.8kHz)
    U_DOWNSAMPLE : integrate_and_dump
    port map(
        clk => clk, reset => reset,
        data_in => adc_data_in, valid_in => adc_valid_in,
        data_out => ds_data, valid_out => ds_valid
    );

    -- Instance 2: Ping-Pong Buffer (BRAM Controller)
    U_BUFFER : fft_ping_pong
    port map(
        clk => clk, reset => reset,
        din_data => ds_data, din_valid => ds_valid,
        m_axis_tdata => axis_tdata,
        m_axis_tvalid => axis_tvalid,
        m_axis_tlast => axis_tlast,
        m_axis_tready => axis_tready
    );

    -- Instance 3: Xilinx FFT IP (8192-point engine)
    U_FFT : xfft_0
    port map(
        aclk => clk,
        aresetn => aresetn,
        s_axis_config_tdata => s_axis_config_tdata,
        s_axis_config_tvalid => not config_done,
        s_axis_config_tready => config_tready,
        s_axis_data_tdata => complex_axis_tdata,
        s_axis_data_tvalid => axis_tvalid,
        s_axis_data_tready => axis_tready,
        s_axis_data_tlast => axis_tlast,
        m_axis_data_tdata => fft_data_internal,
        m_axis_data_tvalid => fft_valid_internal,
        m_axis_data_tlast => fft_last_internal,
        m_axis_data_tready => '1',
        event_frame_started => open
    );

    -- Instance 4: Peak Power Detector
    -- U_PEAK_FINDER : peak_finder
    U_PEAK_FINDER : smart_peak_finder
    port map(
        clk => clk, reset => reset,
        s_axis_tdata => fft_data_internal,
        s_axis_tvalid => fft_valid_internal,
        s_axis_tlast => fft_last_internal,
        peak_bin_index => peak_bin_index,
        peak_ready => internal_ready
    );

    complex_axis_tdata <= x"00000000" & axis_tdata;
    aresetn <= not reset;
    -- Instance 5: Index to Frequency Conversion (Fixed Point Math)
    process (clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                freq_scaled <= (others => '0');
                peak_freq_hz <= (others => '0');
                peak_freq_tenths <= (others => '0');
                tenths_calc <= (others => '0');
                peak_ready <= '0';
            else
                peak_ready <= internal_ready;

                if internal_ready = '1' then
                    freq_scaled <= unsigned(peak_bin_index) * to_unsigned(38400, 16);
                end if;

                -- Integer part (upper bits)
                peak_freq_hz <= std_logic_vector(resize(freq_scaled(28 downto 16), 16));

                -- Multiply the fraction by 10. The new integer part is our 0-9 digit
                tenths_calc <= freq_scaled(15 downto 0) * to_unsigned(10, 4);

                -- The upper 4 bits of this result hold the 0-9 value
                peak_freq_tenths <= std_logic_vector(tenths_calc(19 downto 16));
            end if;
        end if;
    end process;

    process (clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                config_done <= '0';
            elsif config_tready = '1' then
                config_done <= '1'; -- Stop configuring once accepted!
            end if;
        end if;
    end process;

end Structural;