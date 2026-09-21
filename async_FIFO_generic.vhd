----------------------------------------------------------------------------------
-- Project     : Generic Asynchronous FIFO (CDC-safe, Gray-code pointer synchronization)
-- File        : async_FIFO_generic.vhd
-- Author      : Emir Uruc
--
-- Description : Fully parametrizable asynchronous FIFO for crossing two
--               independent, unrelated clock domains (clk_wr / clk_rd).
--               Write and read pointers are converted to Gray code before
--               crossing domains, then passed through an N-stage synchronizer
--               to protect against metastability. full/empty detection uses
--               the standard Gray-code MSB-comparison technique.
--
-- Architecture reference:
-- C. E. Cummings, “Simulation and Synthesis Techniques for Asynchronous FIFO  Design,” SNUG 2002.
-- P. P. Chu, RTL Hardware Design Using VHDL: Coding for Efficiency, Portability,
-- and Scalability, Wiley, 2006 (Chapter 16, FIFO design), consulted for general port structuring ideas.
-- P.P.Chu,FPGAPrototypingbyVHDLExamples,Wiley,2008,consultedasageneral VHDL design and I/O-constraints reference.


-- Generics    :
--   data_width : width of a single FIFO word, in bits
--   addr_width : address width; FIFO depth = 2**addr_width
--   N          : number of synchronizer flip-flop stages (CDC safety margin)
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity async_FIFO_generic is
    generic (
        data_width : integer := 8;
        addr_width : integer := 4;   -- FIFO depth = 2**addr_width (e.g. 4 -> 16 locations, address 0000 to 1111)
        N          : integer := 3    -- number of synchronizer flip-flop stages
    );
    port (
        -- Write port (clk_wr domain)
        clk_wr : in  std_logic;
        rst_wr : in  std_logic;
        en_wr  : in  std_logic;
        din    : in  std_logic_vector(data_width-1 downto 0);
        full   : out std_logic;

        -- Read port (clk_rd domain)
        clk_rd : in  std_logic;
        rst_rd : in  std_logic;
        en_rd  : in  std_logic;
        dout   : out std_logic_vector(data_width-1 downto 0);
        empty  : out std_logic
    );
end async_FIFO_generic;


architecture Behavioral of async_FIFO_generic is

    ------------------------------------------------------------------
    -- Dual-port memory array
    ------------------------------------------------------------------
    type ram_type is array (0 to (2**addr_width)-1) of std_logic_vector(data_width-1 downto 0);
    signal ram : ram_type := (others => (others => '0'));

    ------------------------------------------------------------------
    -- Pointers
    --   Width is addr_width+1: one extra MSB is kept on top of the
    --   address bits so full/empty can be distinguished even when the
    --   pointers wrap around to the same address (see full_o / empty_i
    --   below).
    ------------------------------------------------------------------
    signal wr_ptr_bin : unsigned(addr_width downto 0) := (others => '0');
    signal rd_ptr_bin : unsigned(addr_width downto 0) := (others => '0');

    -- Combinational "next" pointer values (used for RAM addressing /
    -- Gray conversion before the value is actually registered)
    signal wr_ptr_bin_next : unsigned(addr_width downto 0) := (others => '0');
    signal rd_ptr_bin_next : unsigned(addr_width downto 0) := (others => '0');

    -- Registered Gray-code pointers (native domain)
    signal wr_ptr_gray : unsigned(addr_width downto 0) := (others => '0');
    signal rd_ptr_gray : unsigned(addr_width downto 0) := (others => '0');

    -- Combinational "next" Gray-code pointer values
    signal wr_ptr_gray_next : unsigned(addr_width downto 0) := (others => '0');
    signal rd_ptr_gray_next : unsigned(addr_width downto 0) := (others => '0');

    -- Gray-code pointers after crossing into the opposite clock domain
    signal wr_ptr_gray_sync : unsigned(addr_width downto 0) := (others => '0');
    signal rd_ptr_gray_sync : unsigned(addr_width downto 0) := (others => '0');

    ------------------------------------------------------------------
    -- CDC synchronizer registers
    --   Array of N stages; each stage holds one full Gray-code pointer.
    --   Index N-1 is the input stage (fed directly from the source
    --   domain), index 0 is the output stage (used by the destination
    --   domain logic).
    ------------------------------------------------------------------
    type reg is array (0 to N-1) of unsigned(addr_width downto 0);
    signal wr_to_rd_sync_reg : reg := (others => (others => '0'));
    signal rd_to_wr_sync_reg : reg := (others => (others => '0'));

    -- Internal full/empty (kept internal so they can be read back inside
    -- this architecture; full/empty are declared as 'out' ports and
    -- cannot be read directly)
    signal full_o  : std_logic := '0';
    signal empty_i : std_logic := '0';

    ------------------------------------------------------------------
    -- Mark synchronizer registers for placement/timing tools
    ------------------------------------------------------------------
    attribute ASYNC_REG : string;
    attribute ASYNC_REG of wr_to_rd_sync_reg : signal is "TRUE";
    attribute ASYNC_REG of rd_to_wr_sync_reg : signal is "TRUE";

begin

    ------------------------------------------------------------------
    -- Write-side pointer arithmetic and Gray conversion
    --   Pointer holds its value when not writing (no write / full),
    --   so wr_ptr_gray never glitches to zero between writes.
    ------------------------------------------------------------------
    wr_ptr_bin_next  <= wr_ptr_bin + 1 when (en_wr = '1' and full_o = '0') else wr_ptr_bin;
    wr_ptr_gray_next <= wr_ptr_bin_next xor ('0' & wr_ptr_bin_next(addr_width downto 1));

    ------------------------------------------------------------------
    -- Read-side pointer arithmetic and Gray conversion
    ------------------------------------------------------------------
    rd_ptr_bin_next  <= rd_ptr_bin + 1 when (en_rd = '1' and empty_i = '0') else rd_ptr_bin;
    rd_ptr_gray_next <= rd_ptr_bin_next xor ('0' & rd_ptr_bin_next(addr_width downto 1));

    ------------------------------------------------------------------
    -- Full detection (clk_wr domain)
    --   FIFO is full when the write pointer equals the synchronized
    --   read pointer with its top two bits inverted (Gray-code
    --   equivalent of "write pointer is exactly one lap ahead").
    ------------------------------------------------------------------
    full_o <= '1' when wr_ptr_gray = (not rd_ptr_gray_sync(addr_width downto addr_width-1) &
                                       rd_ptr_gray_sync(addr_width-2 downto 0))
              else '0';

    ------------------------------------------------------------------
    -- Empty detection (clk_rd domain)
    --   FIFO is empty when the read pointer has caught up with the
    --   synchronized write pointer (exact Gray-code match).
    ------------------------------------------------------------------
    empty_i <= '1' when rd_ptr_gray = wr_ptr_gray_sync else '0';

    full  <= full_o;
    empty <= empty_i;


    ---------------------------------------------------------
    -- WRITE PROCESS (clk_wr domain)
    --   Advances the write pointer and stores din into the
    --   RAM location currently pointed to, whenever a write
    --   is requested and the FIFO is not full.
    ---------------------------------------------------------
    P_WRITE : process(clk_wr) begin
        if (rising_edge(clk_wr)) then
            if (rst_wr = '1') then
                wr_ptr_bin  <= (others => '0');
                wr_ptr_gray <= (others => '0');
            elsif (en_wr = '1' and full_o = '0') then
                wr_ptr_bin  <= wr_ptr_bin_next;
                wr_ptr_gray <= wr_ptr_gray_next;
                ram(to_integer(wr_ptr_bin(addr_width-1 downto 0))) <= din;
            end if;
        end if;
    end process P_WRITE;


    ---------------------------------------------------------
    -- READ PROCESS (clk_rd domain)
    --   Advances the read pointer and outputs the RAM word
    --   at the current read address, whenever a read is
    --   requested and the FIFO is not empty.
    ---------------------------------------------------------
    P_READ : process(clk_rd) begin
        if (rising_edge(clk_rd)) then
            if (rst_rd = '1') then
                rd_ptr_bin  <= (others => '0');
                rd_ptr_gray <= (others => '0');
                dout        <= (others => '0');
            elsif (en_rd = '1' and empty_i = '0') then
                rd_ptr_bin  <= rd_ptr_bin_next;
                rd_ptr_gray <= rd_ptr_gray_next;
                dout        <= ram(to_integer(rd_ptr_bin(addr_width-1 downto 0)));
            end if;
        end if;
    end process P_READ;


    ---------------------------------------------------------
    -- SYNCHRONIZER: write pointer (Gray) -> read domain
    --   N-stage shift register, clocked by clk_rd. Stage N-1
    --   is loaded with the raw (asynchronous) wr_ptr_gray;
    --   each lower stage shifts in the value of the stage
    --   above it. Stage 0 is the settled, safe-to-use value.
    ---------------------------------------------------------
    P_WR_TO_RD : process(clk_rd) begin
        if (rising_edge(clk_rd)) then
            if (rst_rd = '1') then
                wr_to_rd_sync_reg <= (others => (others => '0'));
            else
                wr_to_rd_sync_reg(N-1) <= wr_ptr_gray;
                for i in 0 to N-2 loop
                    wr_to_rd_sync_reg(i) <= wr_to_rd_sync_reg(i+1);
                end loop;
            end if;
        end if;
    end process P_WR_TO_RD;

    wr_ptr_gray_sync <= wr_to_rd_sync_reg(0);


    ---------------------------------------------------------
    -- SYNCHRONIZER: read pointer (Gray) -> write domain
    --   Mirror of P_WR_TO_RD, clocked by clk_wr.
    ---------------------------------------------------------
    P_RD_TO_WR : process(clk_wr) begin
        if (rising_edge(clk_wr)) then
            if (rst_wr = '1') then
                rd_to_wr_sync_reg <= (others => (others => '0'));
            else
                rd_to_wr_sync_reg(N-1) <= rd_ptr_gray;
                for i in 0 to N-2 loop
                    rd_to_wr_sync_reg(i) <= rd_to_wr_sync_reg(i+1);
                end loop;
            end if;
        end if;
    end process P_RD_TO_WR;

    rd_ptr_gray_sync <= rd_to_wr_sync_reg(0);

end Behavioral;
