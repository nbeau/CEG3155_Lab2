library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity alu_top is
  port(
    GClock          : in  std_logic;
    GReset          : in  std_logic;
    OperandA        : in  std_logic_vector(3 downto 0);
    OperandB        : in  std_logic_vector(3 downto 0);
    OperationSelect : in  std_logic_vector(1 downto 0); -- 00 add, 01 sub, 10 mul, 11 div
    MuxOut          : out std_logic_vector(7 downto 0);
    CarryOut        : out std_logic;
    ZeroOut         : out std_logic;
    OverflowOut     : out std_logic
  );
end entity;

architecture rtl of alu_top is
  --------------------------------------------------------------------
  -- 加/减
  --------------------------------------------------------------------
  signal add_s  : std_logic_vector(3 downto 0);
  signal add_c  : std_logic;
  signal add_ov : std_logic;
  signal sub_s  : std_logic_vector(3 downto 0);
  signal sub_c  : std_logic;
  signal sub_ov : std_logic;

  --------------------------------------------------------------------
  -- 乘法（Booth） + 自动触发
  --------------------------------------------------------------------
  signal mul_start   : std_logic := '0';
  signal mul_done    : std_logic;
  signal mul_p       : std_logic_vector(7 downto 0);
  signal prod_reg    : std_logic_vector(7 downto 0) := (others => '0');

  signal mul_last_A  : std_logic_vector(3 downto 0) := (others => '0');
  signal mul_last_B  : std_logic_vector(3 downto 0) := (others => '0');
  signal mul_running : std_logic := '0';
  signal mul_inited  : std_logic := '0';

  --------------------------------------------------------------------
  -- 除法（非恢复） + 可选自动触发（同样避免 others 聚合）
  --------------------------------------------------------------------
  signal div_start   : std_logic := '0';
  signal div_done    : std_logic;
  signal div_div0    : std_logic;
  signal div_q_wire  : std_logic_vector(3 downto 0);
  signal div_r_wire  : std_logic_vector(3 downto 0);
  signal div_q       : std_logic_vector(3 downto 0) := (others => '0');
  signal div_r       : std_logic_vector(3 downto 0) := (others => '0');
  signal div_running : std_logic := '0';
  signal div_inited  : std_logic := '0';
  signal div_last_A  : std_logic_vector(3 downto 0) := (others => '0');
  signal div_last_B  : std_logic_vector(3 downto 0) := (others => '0');

  --------------------------------------------------------------------
  -- 选择与输出
  --------------------------------------------------------------------
  signal sel     : std_logic_vector(1 downto 0);
  signal out_bus : std_logic_vector(7 downto 0);

  signal div_overflow : std_logic;

begin
  sel <= OperationSelect;

  --------------------------------------------------------------------
  -- Adder / Subtractor
  --------------------------------------------------------------------
  U_ADD: entity work.addsub_n
    generic map (N => 4)
    port map(
      A      => OperandA,
      B      => OperandB,
      AddSub => '0',
      S      => add_s,
      Cout   => add_c,
      V_ovf  => add_ov
    );

  U_SUB: entity work.addsub_n
    generic map (N => 4)
    port map(
      A      => OperandA,
      B      => OperandB,
      AddSub => '1',
      S      => sub_s,
      Cout   => sub_c,
      V_ovf  => sub_ov
    );

  --------------------------------------------------------------------
  -- Booth Multiplier
  --------------------------------------------------------------------
  U_MUL: entity work.booth_mul4
    port map(
      clk   => GClock,
      rst   => GReset,
      start => mul_start,
      A_in  => OperandA,
      B_in  => OperandB,
      done  => mul_done,
      P_out => mul_p
    );

  --------------------------------------------------------------------
  -- Signed Non-Restoring Divider
  --------------------------------------------------------------------
  U_DIV: entity work.nr_div4_signed
    port map(
      clk      => GClock,
      rst      => GReset,
      start    => div_start,
      Dividend => OperandA,
      Divisor  => OperandB,
      done     => div_done,
      Q_out    => div_q_wire,
      R_out    => div_r_wire,
      div0     => div_div0
    );

  --------------------------------------------------------------------
  -- 自动触发控制
  -- 乘法：sel="10" 且（尚未计算过 或 A/B 与上次不同）→ 单拍 start
  -- 除法：sel="11" 同理（若不想自动，删掉其触发判断即可）
  --------------------------------------------------------------------
  process(GClock)
    variable need_mul : boolean;
    variable need_div : boolean;
  begin
    if rising_edge(GClock) then
      if GReset = '1' then
        -- mul
        mul_start   <= '0';
        mul_running <= '0';
        mul_inited  <= '0';
        prod_reg    <= (others => '0');
        mul_last_A  <= (others => '0');
        mul_last_B  <= (others => '0');
        -- div
        div_start   <= '0';
        div_running <= '0';
        div_inited  <= '0';
        div_q       <= (others => '0');
        div_r       <= (others => '0');
        div_last_A  <= (others => '0');
        div_last_B  <= (others => '0');
      else
        -- 默认单拍
        mul_start <= '0';
        div_start <= '0';

        -- 乘法自动触发
        need_mul := (sel = "10") and (mul_running = '0') and
                    ((mul_inited = '0') or
                     (OperandA /= mul_last_A) or
                     (OperandB /= mul_last_B));
        if need_mul then
          mul_start   <= '1';
          mul_running <= '1';
        end if;

        if mul_done = '1' then
          prod_reg    <= mul_p;
          mul_last_A  <= OperandA;
          mul_last_B  <= OperandB;
          mul_running <= '0';
          mul_inited  <= '1';
        end if;

        -- 除法自动触发（可保留/可删）
        need_div := (sel = "11") and (div_running = '0') and
                    ((div_inited = '0') or
                     (OperandA /= div_last_A) or
                     (OperandB /= div_last_B));
        if need_div then
          div_start   <= '1';
          div_running <= '1';
        end if;

        if div_done = '1' then
          div_q       <= div_q_wire;
          div_r       <= div_r_wire;
          div_last_A  <= OperandA;
          div_last_B  <= OperandB;
          div_running <= '0';
          div_inited  <= '1';
        end if;
      end if;
    end if;
  end process;

  --------------------------------------------------------------------
  -- 输出多路（与实验表 4 对齐）
  --------------------------------------------------------------------
  out_bus <= ("0000" & add_s) when (sel = "00") else
             ("0000" & sub_s) when (sel = "01") else
             (prod_reg)        when (sel = "10") else
             (div_r & div_q);  -- "11"
  MuxOut <= out_bus;

  --------------------------------------------------------------------
  -- 标志位
  --------------------------------------------------------------------
  CarryOut <= add_c       when (sel = "00") else
              (not sub_c) when (sel = "01") else
              '0';

  -- 4 位两补数特殊溢出：-8 / -1 = +8（超 4 位）
  div_overflow <= '1' when (sel = "11" and OperandA = "1000" and OperandB = "1111") else '0';

  OverflowOut <= add_ov when (sel = "00") else
                 sub_ov when (sel = "01") else
                 div_overflow;

  ZeroOut <= '1' when out_bus = x"00" else '0';

end architecture;
