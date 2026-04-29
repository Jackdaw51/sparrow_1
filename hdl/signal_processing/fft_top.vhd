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

        -- FFT Result Interface (To Magnitude Calculator or CPU)
        fft_data_out : out std_logic_vector(63 downto 0); -- [31:0] Imag, [63:32] Real
        fft_valid_out : out std_logic;
        fft_last_out : out std_logic
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

    -- 3. FFT Configuration (Always static for our needs)
    -- Config: [7:0] Padding, [15:8] Forward/Inv (1=Fwd), [23:16] Scale Schedule
    signal s_axis_config_tdata : std_logic_vector(15 downto 0) := x"0001";
    signal s_axis_config_tvalid : std_logic := '1';

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
            s_axis_config_tdata : in std_logic_vector(15 downto 0);
            s_axis_config_tvalid : in std_logic;
            s_axis_config_tready : out std_logic;
            s_axis_data_tdata : in std_logic_vector(31 downto 0);
            s_axis_data_tvalid : in std_logic;
            s_axis_data_tready : out std_logic;
            s_axis_data_tlast : in std_logic;
            m_axis_data_tdata : out std_logic_vector(63 downto 0);
            m_axis_data_tvalid : out std_logic;
            m_axis_data_tlast : out std_logic;
            event_frame_started : out std_logic
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
        s_axis_config_tdata => s_axis_config_tdata,
        s_axis_config_tvalid => s_axis_config_tvalid,
        s_axis_config_tready => open, -- We ignore this as config is static
        s_axis_data_tdata => axis_tdata,
        s_axis_data_tvalid => axis_tvalid,
        s_axis_data_tready => axis_tready,
        s_axis_data_tlast => axis_tlast,
        m_axis_data_tdata => fft_data_out,
        m_axis_data_tvalid => fft_valid_out,
        m_axis_data_tlast => fft_last_out,
        event_frame_started => open
    );

end Structural;