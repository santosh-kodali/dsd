library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_unsigned.ALL;
use IEEE.numeric_std.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity PDMPCM is
    Port ( clk : in STD_LOGIC;
         en : in std_logic;
        pdm : in STD_LOGIC;
        pcm: out STD_LOGIC_VECTOR (6 downto 0);
        done: out STD_LOgic );
end PDMPCM;

architecture Behavioral of PDMPCM is
type states is (S0,S1);
signal pr_state,nxt_state:states:=S0;
signal count :integer:=0;
signal pcm1: STD_LOGIC_VECTOR (6 downto 0):="0000000";
begin
process(clk)
begin
    if clk'event and clk='1' then
    pr_state<=nxt_state;
    end if;
end process;

process(pr_state,clk)
begin
if rising_edge(clk) then
     nxt_state<=pr_state;
    
case pr_state is
   when S0=>
    count<=0;
    nxt_state<=S1;
    pcm1<="0000000";
        
    when S1=>
    if count=127 then
    pcm1<="0000000";
    count <= 0;
    done <= '1';
    nxt_state<=S1;
    else
    done <= '0'; 
    pcm1 <= pcm1 + pdm;
    count <= count+1;
    nxt_state<=S1;
    end if;
   end case;
   end if; 
    end process;

pcm<=pcm1;



end Behavioral;