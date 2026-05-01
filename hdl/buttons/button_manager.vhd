library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity button_manager is
    port (
        clk_100_buffered : in std_logic; --Clock
        buttons_in  : in  std_logic_vector(4 downto 0);
        buttons_deb : out std_logic_vector(4 downto 0);
        btnl_impulse: out std_logic;
        btnr_impulse: out std_logic
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

    signal btn_deb : std_logic_vector(4 downto 0);

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
                sig_out => btn_deb(i)
            );
    end generate GEN_DEBOUNCERS;

    Impulse_generator: process (clk_100_buffered)
        variable btnl_prev : std_logic := '0';
        variable btnr_prev : std_logic := '0';
    begin
        if rising_edge(clk_100_buffered) then   
            -- Generate impulse for btnl (button 0)
            if btn_deb(3) = '1' and btnl_prev = '0' then
                btnl_impulse <= '1';
            else
                btnl_impulse <= '0';
            end if;
            btnl_prev := btn_deb(3);

            -- Generate impulse for btnr (button 1)
            if btn_deb(4) = '1' and btnr_prev = '0' then
                btnr_impulse <= '1';
            else
                btnr_impulse <= '0';
            end if;
            btnr_prev := btn_deb(4);
        end if;
    end process;

    buttons_deb <= btn_deb;

end Structural;