library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity button_manager is
    port (
        clk_100_buffered : in std_logic; --Clock
        buttons_in  : in  std_logic_vector(4 downto 0);
        buttons_deb : out std_logic_vector(4 downto 0)
    );
end entity button_manager;


architecture Structural of button_manager is
    -- Component declaration
    component debouncer
        Generic (
            WAIT_CYCLES : integer
        );
        Port (
            clk, sig_in : in std_logic;
            sig_out : out std_logic
        );
    end component;

begin
    -- The "Loop Unrolling" (Generate Statement)
    GEN_DEBOUNCERS: for i in 0 to 4 generate
        debouncer_inst : debouncer
            generic map (
                WAIT_CYCLES => 2_000_000 -- 20ms for mechanical switches
            )
            port map (
                clk     => clk_100_buffered,
                sig_in  => buttons_in(i),
                sig_out => buttons_deb(i)
            );
    end generate GEN_DEBOUNCERS;

end Structural;