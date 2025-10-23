-- addsub_n.vhd (fixed: avoid reading 'out' port S)
library ieee;
use ieee.std_logic_1164.all;

entity addsub_n is
  generic(N : integer := 4);
  port(
    A       : in  std_logic_vector(N-1 downto 0);
    B       : in  std_logic_vector(N-1 downto 0);
    AddSub  : in  std_logic;  -- 0: add, 1: subtract (A - B)
    S       : out std_logic_vector(N-1 downto 0);
    Cout    : out std_logic;  -- 进位(加)/借位(减)（RCA的cout）
    V_ovf   : out std_logic   -- 二补码溢出指示
  );
end entity;

architecture structural of addsub_n is
  component rca_n
    generic(N : integer := 4);
    port(
      a    : in  std_logic_vector(N-1 downto 0);
      b    : in  std_logic_vector(N-1 downto 0);
      cin  : in  std_logic;
      s    : out std_logic_vector(N-1 downto 0);
      cout : out std_logic
    );
  end component;

  signal Bx    : std_logic_vector(N-1 downto 0);
  signal S_int : std_logic_vector(N-1 downto 0);  -- 内部和/差
  signal c_out : std_logic;
begin
  -- 条件取反：AddSub=1 时对 B 取反
  gen_xor: for i in 0 to N-1 generate
    Bx(i) <= B(i) xor AddSub;
  end generate;

  -- 串行进位加法器：Cin = AddSub，实现 A + B 或 A + (~B) + 1
  U_RCA: rca_n
    generic map(N => N)
    port map(
      a    => A,
      b    => Bx,
      cin  => AddSub,
      s    => S_int,
      cout => c_out
    );

  -- 对外端口赋值
  S    <= S_int;
  Cout <= c_out;

  -- 二补码溢出（同号相加得异号）
  V_ovf <= (A(N-1) and Bx(N-1) and (not S_int(N-1))) or
           ((not A(N-1)) and (not Bx(N-1)) and S_int(N-1));
end architecture;
