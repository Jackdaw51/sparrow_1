library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity switch_manager is
    port (
        clk_100_buffered : in std_logic; --Clock
        switches_in : in std_logic_vector(7 downto 0);
        switches_deb : out std_logic_vector(7 downto 0);
        switches_valid : out std_logic
    );
end entity switch_manager;
architecture Structural of switch_manager is
    -- Component declaration
    component debouncer
        generic (
            WAIT_CYCLES : integer
        );
        port (
            clk_100, sig_in : in std_logic;
            sig_out : out std_logic
        );
    end component;

    signal sw_deb : std_logic_vector(7 downto 0);

begin
    -- The "Loop Unrolling" (Generate Statement)
    GEN_DEBOUNCERS : for i in 0 to 7 generate
        debouncer_inst : debouncer
        generic map(
            WAIT_CYCLES => 2_000_000 -- 20ms for mechanical switches
        )
        port map(
            clk_100 => clk_100_buffered,
            sig_in => switches_in(i),
            sig_out => sw_deb(i)
        );
    end generate GEN_DEBOUNCERS;

    Checker : process (clk_100_buffered)
        variable count : integer range 0 to 8;
    begin
        if rising_edge(clk_100_buffered) then
            count := 0;
            for i in sw_deb'range loop
                if sw_deb(i) = '1' then
                    count := count + 1;
                end if;
            end loop;

            if count > 1 then
                switches_valid <= '0';
            else
                switches_valid <= '1';
            end if;
        end if;
    end process;

    switches_deb <= sw_deb;
end Structural;