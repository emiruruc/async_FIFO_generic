----------------------------------------------------------------------------------
-- Project     : Generic Asynchronous FIFO (CDC-safe, Gray-code pointer synchronization)
-- File        : tb3_async_FIFO_generic.vhd
-- Author      : Emir Uruc
--
-- Description : Testbench 3 - Simultaneous write + read stress test.
--               Pre-loads the FIFO to a mid-depth state (9 words, 0x00..0x08),
--               then holds en_wr and en_rd high at the same time for 200 ns,
--               with din fixed at 0xAA, so both the write and read processes
--               run concurrently and independently for many clk_wr/clk_rd
--               cycles. This exercises the case where the FIFO is neither
--               full nor empty while both domains are active simultaneously.
--
-- What to check in the waveform:
--   - full and empty must never both be '0'->'1' at the same instant
--     (mutually exclusive by construction, this test confirms it holds
--     under concurrent read/write traffic as well)
--   - dout must still return 0x01, 0x02, ... 0x08 in order before the
--     freshly-written 0xAA values start appearing
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity tb3_async_FIFO_generic is
    generic (
        data_width : integer := 8;
        addr_width : integer := 4;   -- FIFO depth = 2**addr_width = 16 locations (address 0000 to 1111)
        N          : integer := 3    -- number of synchronizer flip-flop stages
    );
end tb3_async_FIFO_generic;


architecture Behavioral of tb3_async_FIFO_generic is

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

        -- Pre-load the FIFO to a mid-depth state: 9 writes (0x00 .. 0x08).
        -- Leaves the FIFO neither full nor empty before the concurrent phase.
        for i in 0 to 8 loop
            wait until falling_edge(clk_wr);
            en_wr <= '1';
            din   <= std_logic_vector(to_unsigned(i, data_width));
            wait until rising_edge(clk_wr);
            en_wr <= '0';
        end loop;

        wait for 100 ns;

        -- Enable simultaneous write and read: both processes run
        -- independently, on their own clock, for the same time window.
        -- din is held fixed at 0xAA (content is not the point of this
        -- test - concurrency and full/empty consistency are).
        wait until falling_edge(clk_wr);
        en_wr <= '1';
        en_rd <= '1';
        din   <= x"AA";

        wait for 200 ns;

        en_wr <= '0';
        en_rd <= '0';

        wait for 200 ns;

        assert false
            report "SIM DONE"
            severity failure;

    end process P_STIMULI;

end Behavioral;