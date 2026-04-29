library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity fft_ping_pong is
    port (
        clk           : in  std_logic;
        reset         : in  std_logic;
        din_data      : in  std_logic_vector(31 downto 0);
        din_valid     : in  std_logic;
        m_axis_tdata  : out std_logic_vector(31 downto 0);
        m_axis_tvalid : out std_logic;
        m_axis_tlast  : out std_logic;
        m_axis_tready : in  std_logic
    );
end fft_ping_pong;

architecture Structural of fft_ping_pong is

    -- Component Declaration for the IP you generated
    COMPONENT blk_mem_gen_0
      PORT (
        clka  : IN STD_LOGIC;
        wea   : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
        addra : IN STD_LOGIC_VECTOR(13 DOWNTO 0); -- 16384 needs 14 bits
        dina  : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
        clkb  : IN STD_LOGIC;
        addrb : IN STD_LOGIC_VECTOR(13 DOWNTO 0);
        doutb : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
      );
    END COMPONENT;

    -- Signals to connect to the IP
    signal wr_ptr     : unsigned(12 downto 0) := (others => '0');
    signal rd_ptr     : unsigned(12 downto 0) := (others => '0');
    signal write_bank : std_logic := '0';
    signal b_addr_a   : std_logic_vector(13 downto 0);
    signal b_addr_b   : std_logic_vector(13 downto 0);
    
    type state_type is (IDLE, FEED_FFT);
    signal state : state_type := IDLE;

begin

    -- Address Logic: Bank bit (MSB) + Pointer
    b_addr_a <= write_bank & std_logic_vector(wr_ptr);
    b_addr_b <= (not write_bank) & std_logic_vector(rd_ptr);

    -- Instantiate the BRAM IP
    your_bram_inst : blk_mem_gen_0
      PORT MAP (
        clka  => clk,
        wea(0)=> din_valid,
        addra => b_addr_a,
        dina  => din_data,
        clkb  => clk,
        addrb => b_addr_b,
        doutb => m_axis_tdata -- Connects directly to FFT stream
      );

    -- State Machine & Pointer Logic
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                wr_ptr <= (others => '0');
                rd_ptr <= (others => '0');
                write_bank <= '0';
                state <= IDLE;
                m_axis_tvalid <= '0';
                m_axis_tlast <= '0';
            else
                -- Write Pointer Logic (Slow side)
                if din_valid = '1' then
                    if wr_ptr = 8191 then
                        wr_ptr <= (others => '0');
                        write_bank <= not write_bank;
                    else
                        wr_ptr <= wr_ptr + 1;
                    end if;
                end if;

                -- Read State Machine (Fast side)
                m_axis_tlast <= '0'; -- Default
                case state is
                    when IDLE =>
                        m_axis_tvalid <= '0';
                        -- Wait for the write pointer to flip, indicating a bank is ready
                        if wr_ptr = 0 and din_valid = '1' then
                            state <= FEED_FFT;
                        end if;

                    when FEED_FFT =>
                        if m_axis_tready = '1' then
                            m_axis_tvalid <= '1';
                            if rd_ptr = 8191 then
                                m_axis_tlast <= '1';
                                rd_ptr <= (others => '0');
                                state <= IDLE;
                            else
                                rd_ptr <= rd_ptr + 1;
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process;

end Structural;