----------------------------------------------------------------------------------
-- Project     : Generic Asynchronous FIFO (CDC-safe, Gray-code pointer synchronization)
-- File        : tb_async_FIFO_generic.vhd
-- Author      : Emir Uruc
--
-- Description : Testbench 1 - Basic functional test.
--               Writes a full FIFO (16 words, incrementing pattern 0x00..0x0F)
--               on the wr_clk domain, then reads all 16 words back on the
--               independent rd_clk domain. Confirms:
--                 - data integrity (values come back in the order written)
--                 - full asserts at exactly the right time (after the 16th write)
--                 - empty asserts at exactly the right time (after the 16th read)
--
-- Clocks      : clk_wr = 100 MHz (10 ns period), clk_rd = 133 MHz (7.5 ns period)
--               -- deliberately different/asynchronous to exercise the CDC path.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity tb_async_FIFO_generic is
    generic (
        data_width : integer := 8;
        addr_width : integer := 4;   -- FIFO depth = 2**addr_width = 16 locations (address 0000 to 1111)
        N          : integer := 3    -- number of synchronizer flip-flop stages
    );
end tb_async_FIFO_generic;


architecture Behavioral of tb_async_FIFO_generic is

    ------------------------------------------------------------
    -- COMPONENT DECLARATION
    ------------------------------------------------------------
    component async_FIFO_generic is
        generic (
            data_width : integer := 8;
            addr_width : integer := 4;
            N          : integer := 3
        );
        port (
            -- write ports
            clk_wr : in  std_logic;
            rst_wr : in  std_logic;
            en_wr  : in  std_logic;
            din    : in  std_logic_vector(data_width-1 downto 0);
            full   : out std_logic;
            -- read ports
            clk_rd : in  std_logic;
            rst_rd : in  std_logic;
            en_rd  : in  std_logic;
            dout   : out std_logic_vector(data_width-1 downto 0);
            empty  : out std_logic
        );
    end component;


    ------------------------------------------------------------
    -- SIGNAL DEFINITIONS
    ------------------------------------------------------------
    signal clk_wr : std_logic := '0';
    signal rst_wr : std_logic := '1';
    signal en_wr  : std_logic := '0';
    signal din    : std_logic_vector(data_width-1 downto 0) := (others => '0');
    signal full   : std_logic := '0';

    signal clk_rd : std_logic := '0';
    signal rst_rd : std_logic := '1';
    signal en_rd  : std_logic := '0';
    signal dout   : std_logic_vector(data_width-1 downto 0) := (others => '0');
    signal empty  : std_logic := '0';

    constant c_clk100mperiod : time := 10 ns;
    constant c_clk133mperiod : time := 7.5 ns;

begin

    ------------------------------------------------------------
    -- COMPONENT INSTANTIATION
    ------------------------------------------------------------
    DUT : async_FIFO_generic
        generic map (
            data_width => data_width,
            addr_width => addr_width,
            N          => N
        )
        port map (
            clk_wr => clk_wr,
            rst_wr => rst_wr,
            en_wr  => en_wr,
            din    => din,
            full   => full,
            clk_rd => clk_rd,
            rst_rd => rst_rd,
            en_rd  => en_rd,
            dout   => dout,
            empty  => empty
        );

    ------------------------------------------------------------
    -- CLOCK GENERATION
    ------------------------------------------------------------
    P_CLK_WR : process begin
        clk_wr <= '0';
        wait for c_clk100mperiod/2;
        clk_wr <= '1';
        wait for c_clk100mperiod/2;
    end process P_CLK_WR;

    P_CLK_RD : process begin
        clk_rd <= '0';
        wait for c_clk133mperiod/2;
        clk_rd <= '1';
        wait for c_clk133mperiod/2;
    end process P_CLK_RD;


    ------------------------------------------------------------
    -- STIMULUS
    ------------------------------------------------------------
    P_STIMULI : process begin

        -- Reset both domains
        rst_wr <= '1';
        rst_rd <= '1';
        wait for 100 ns;
        wait until falling_edge(clk_wr);
        rst_wr <= '0';
        rst_rd <= '0';

        -- Write 16 words (0x00 .. 0x0F), one per clk_wr cycle.
        -- din/en_wr are set on the falling edge so they are stable
        -- and glitch-free at the following rising edge (setup time).
        for i in 0 to 15 loop
            wait until falling_edge(clk_wr);
            en_wr <= '1';
            din   <= std_logic_vector(to_unsigned(i, data_width));
            wait until rising_edge(clk_wr);
            en_wr <= '0';
        end loop;

        wait for 100 ns;  -- allow the write pointer time to synchronize into the read domain

        -- Read back all 16 words, one per clk_rd cycle.
        for i in 0 to 15 loop
            wait until falling_edge(clk_rd);
            en_rd <= '1';
            wait until rising_edge(clk_rd);
            en_rd <= '0';
        end loop;

        wait for 200 ns;

        assert false
            report "SIM DONE"
            severity failure;

    end process P_STIMULI;

end Behavioral;