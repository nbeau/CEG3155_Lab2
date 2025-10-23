-- rca_n.vhd
library ieee;
use ieee.std_logic_1164.all;

entity rca_n is
  generic(N : integer := 4);  -- 默认 4 位，跟实验后续一致
  port(
    a    : in  std_logic_vector(N-1 downto 0);
    b    : in  std_logic_vector(N-1 downto 0);
    cin  : in  std_logic;
    s    : out std_logic_vector(N-1 downto 0);
    cout : out std_logic
  );
end entity;

architecture structural of rca_n is
  component full_adder
    port(a, b, cin: in std_logic; s, cout: out std_logic);
  end component;

  signal c : std_logic_vector(N downto 0);
begin
  c(0) <= cin;

  gen: for i in 0 to N-1 generate
    fa_i: full_adder
      port map(
        a    => a(i),
        b    => b(i),
        cin  => c(i),
        s    => s(i),
        cout => c(i+1)
      );
  end generate;

  cout <= c(N);
end architecture;
