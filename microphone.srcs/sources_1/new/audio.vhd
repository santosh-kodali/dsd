----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use IEEE.math_real.all;

----------------------------------------------------------------------------------

entity audio is
   port(
      clk_i          : in    std_logic;
      rstn_i         : in    std_logic;
      
      -- Peripherals
      btn_u          : in    std_logic;
      leds_o         : out   std_logic_vector(15 downto 0);
      
      -- Microphone PDM signals
      pdm_m_clk_o    : out   std_logic; -- Output M_CLK signal to the microphone
      pdm_m_data_i   : in    std_logic; -- Input PDM data from the microphone
      pdm_lrsel_o    : out   std_logic; -- Set to '0', therefore data is read on the positive edge
      
      -- Audio output signals
      pwm_audio_o    : out   std_logic; -- Output Audio data to the lowpass filters
      pwm_sdaudio_o  : out   std_logic; -- Output Audio enable
      
      -- RAM signals
      Mem_A          : out   std_logic_vector(22 downto 0);
      Mem_DQ         : inout std_logic_vector(15 downto 0);
      Mem_CEN        : out   std_logic;
      Mem_OEN        : out   std_logic;
      Mem_WEN        : out   std_logic;
      Mem_UB         : out   std_logic;
      Mem_LB         : out   std_logic;
      Mem_ADV        : out   std_logic;
      Mem_CLK        : out   std_logic;
      Mem_CRE        : out   std_logic
   );
end audio;

architecture Behavioral of audio is

--pdm to pcm
component PDMPCM is
Port ( clk : in STD_LOGIC;
        en : in std_logic;
        pdm : in STD_LOGIC;
        pcm: out STD_LOGIC_VECTOR (6 downto 0);
        done: out std_logic);
end component;


-- Memory Controller
component PsramCntrl is
generic (
   C_RW_CYCLE_NS  : integer := 100);
port (
   clk_i          : in  std_logic; -- 100 MHz system clock
   rst_i          : in  std_logic; -- active high system reset
   rnw_i          : in  std_logic; -- read/write
   be_i           : in  std_logic_vector(3 downto 0); -- byte enable
   addr_i         : in  std_logic_vector(31 downto 0); -- address input
   data_i         : in  std_logic_vector(31 downto 0); -- data input
   cs_i           : in  std_logic; -- active high chip select
   data_o         : out std_logic_vector(31 downto 0); -- data output
   rd_ack_o       : out std_logic; -- read acknowledge flag
   wr_ack_o       : out std_logic; -- write acknowledge flag
   -- PSRAM Memory signals
   Mem_A          : out std_logic_vector(22 downto 0);
   Mem_DQ_O       : out std_logic_vector(15 downto 0);
   Mem_DQ_I       : in  std_logic_vector(15 downto 0);
   Mem_DQ_T       : out std_logic_vector(15 downto 0);
   Mem_CEN        : out std_logic;
   Mem_OEN        : out std_logic;
   Mem_WEN        : out std_logic;
   Mem_UB         : out std_logic;
   Mem_LB         : out std_logic;
   Mem_ADV        : out std_logic;
   Mem_CLK        : out std_logic;
   Mem_CRE        : out std_logic;
   Mem_Wait       : in  std_logic);
end component;



-- Led-Bar
component LedBar is
generic(
   C_SYS_CLK_FREQ_MHZ  : integer := 100;
   C_SECONDS_TO_RECORD : integer := 3);
port(
   clk_i  : in  std_logic; -- system clock
   rst_i  : in  std_logic; -- active-high reset
   en_i   : in  std_logic; -- active-high enable
   rnl_i  : in  std_logic; -- Right/Left shift select
   leds_o : out std_logic_vector(15 downto 0)); -- output LED bus
end component;

------------------------------------------------------------------------
-- Constant Declarations
------------------------------------------------------------------------
constant SECONDS_TO_RECORD    : integer := 5;
constant PDM_FREQ_HZ          : integer := 1560000; --1687500;

constant SYS_CLK_FREQ_MHZ     : integer := 100;
constant NR_OF_BITS           : integer := 7;
constant NR_SAMPLES_TO_REC    : integer := (((SECONDS_TO_RECORD*PDM_FREQ_HZ)/128)); -- maybe -1 

-- used to concatenate the 32-bit write data of the memory controller
-- from the deserializer
constant DATA_CONCAT : std_logic_vector (32 - NR_OF_BITS - 1 downto 0) := (others =>'0');
------------------------------------------------------------------------
-- Local Type Declarations
------------------------------------------------------------------------
type state_type is (stIdle, stRecord, stInter, stPlayback);

------------------------------------------------------------------------
-- Signal Declarations
------------------------------------------------------------------------
signal state, next_state : state_type;

-- common
signal rst_i : std_logic;
signal rnw_int : std_logic;
signal addr_int : std_logic_vector(31 downto 0);
signal done_int : std_logic;
signal Mem_DQ_O, Mem_DQ_I, Mem_DQ_T : std_logic_vector(15 downto 0);

signal mem_data_i : std_logic_vector (31 downto 0) := (others => '0');
signal mem_data_o : std_logic_vector (31 downto 0) := (others => '0');

-- record
signal pcmpdm_enable : std_logic;

signal pcm_done : std_logic;
signal pcm_data : std_logic_vector(NR_OF_BITS - 1 downto 0);
signal addr_rec : std_logic_vector(31 downto 0) := (others => '0');
signal cntRecSamples : integer := 0;
signal done_pcm_dly : std_logic;

-- playback
signal en_ser : std_logic;
signal done_ser : std_logic;
signal rd_ack_int : std_logic;
signal data_ser : std_logic_vector(NR_OF_BITS - 1 downto 0);
signal data_ser0 : std_logic_vector(NR_OF_BITS - 1 downto 0);
signal addr_play : std_logic_vector(31 downto 0) := (others => '0');
signal cntPlaySamples : integer := 0;
signal done_ser_dly : std_logic;

-- led-bar
signal en_leds : std_logic;
signal rnl_int : std_logic;

attribute FSM_ENCODING : string;
attribute FSM_ENCODING of state: signal is "GRAY";

------------------------------------------------------------------------
-- Module Implementation
------------------------------------------------------------------------
begin
   
   rst_i <= not rstn_i;
   
   -- memory bidirectional bus buffer
   Mem_DQ <= Mem_DQ_O when Mem_DQ_T = x"0000" else (others => 'Z');
   Mem_DQ_I <= Mem_DQ;


mem_data_i <= DATA_CONCAT & pcm_data;


 pdmpcmCtrl: PDMPCM
 port map ( clk => clk_i,
         en => pcmpdm_enable,
         pdm => pdm_m_data_i,
         pcm => pcm_data,
         done => pcm_done);


   MemCtrl: PsramCntrl
   generic map(
      C_RW_CYCLE_NS => 100)
   port map(
      clk_i          => clk_i,
      rst_i          => rst_i,
      rnw_i          => rnw_int,
      be_i           => "0011", -- 16-bit
      addr_i         => addr_int,
      data_i         => mem_data_i,
      cs_i           => done_int,
      data_o         => mem_data_o,
      rd_ack_o       => rd_ack_int,
      wr_ack_o       => open,
      Mem_A          => Mem_A,
      Mem_DQ_O       => Mem_DQ_O,
      Mem_DQ_I       => Mem_DQ_I,
      Mem_DQ_T       => Mem_DQ_T,
      Mem_CEN        => Mem_CEN,
      Mem_OEN        => Mem_OEN,
      Mem_WEN        => Mem_WEN,
      Mem_UB         => Mem_UB,
      Mem_LB         => Mem_LB,
      Mem_ADV        => Mem_ADV,
      Mem_CLK        => Mem_CLK,
      Mem_CRE        => Mem_CRE,
      Mem_Wait       => '0');
   
   done_int <= pcm_done;
      

   -- Count the recorded samples
   process(clk_i)
   begin
      if rising_edge(clk_i) then
         if state = stRecord then
            if pcm_done = '1' then
               cntRecSamples <= cntRecSamples + 1;
            end if;
            if done_pcm_dly = '1' then
               addr_rec <= addr_rec + "10";
            end if;
         else
            cntRecSamples <= 0;
            addr_rec <= (others => '0');
         end if;
         done_pcm_dly <= pcm_done;
      end if;
   end process;

   -- Count the played samples
   process(clk_i)
   begin
      if rising_edge(clk_i) then
         if state = stPlayback then
            if done_ser = '1' then
               cntPlaySamples <= cntPlaySamples + 1;
            end if;
            if done_ser_dly = '1' then
               addr_play <= addr_play + "10";
            end if;
         else
            cntPlaySamples <= 0;
            addr_play <= (others => '0');
         end if;
         done_ser_dly <= done_ser;
      end if;
   end process;

------------------------------------------------------------------------
--  FSM Register Process
------------------------------------------------------------------------
   SYNC_PROC: process(clk_i)
   begin
      if rising_edge(clk_i) then
         if rst_i = '1' then
            state <= stIdle;
         else
            state <= next_state;
         end if;        
      end if;
   end process;
 
   --MEALY State-Machine with registered outputs - Outputs based on state and inputs
   OUTPUT_DECODE: process(clk_i)
   begin
      if rising_edge(clk_i) then
         case (state) is
            when stIdle =>
               rnw_int  <= '0';
               pcmpdm_enable   <= '0';
               addr_int <= (others => '0');
               en_leds  <= '0';
               rnl_int  <= '0';
            when stRecord =>
               rnw_int  <= '0';
               pcmpdm_enable   <= '1';
               
               addr_int <= addr_rec;
               en_leds  <= '1';
               rnl_int  <= '1';
            when stInter =>
               rnw_int  <= '0';
               pcmpdm_enable   <= '0'; 
               addr_int <= (others => '0');
               en_leds  <= '0';
               rnl_int  <= '0';
            when stPlayback =>
               rnw_int  <= '1';
               pcmpdm_enable   <= '1';
               
               addr_int <= addr_play;
               en_leds  <= '1';
               rnl_int  <= '0';
            when others =>
               rnw_int  <= '0';
               pcmpdm_enable   <= '0';             
               addr_int <= (others => '0');
               en_leds  <= '0';
               rnl_int  <= '0';
         end case;
      end if;
   end process;
 
   -- Next state decode process
   NEXT_STATE_DECODE: process(state, btn_u, cntRecSamples, cntPlaySamples)
   begin
      next_state <= state;
      case (state) is
         when stIdle =>
            if btn_u = '1' then
               next_state <= stRecord;
            end if;
         when stRecord =>
            if cntRecSamples = NR_SAMPLES_TO_REC then
               next_state <= stInter;
            end if;
         when stInter =>
            next_state <= stPlayback;
         when stPlayback =>
            if cntPlaySamples = NR_SAMPLES_TO_REC then
               next_state <= stIdle;
            end if;
         when others =>
            next_state <= stIdle;
      end case;      
   end process;

------------------------------------------------------------------------
--  LED-bar display
------------------------------------------------------------------------
	Inst_LedBar: LedBar
   generic map(
      C_SYS_CLK_FREQ_MHZ  => SYS_CLK_FREQ_MHZ,
      C_SECONDS_TO_RECORD => SECONDS_TO_RECORD)
   port map(
      clk_i    => clk_i,
      rst_i    => rst_i,
      en_i     => en_leds,
      rnl_i    => rnl_int,
      leds_o   => leds_o);
   
end Behavioral;
