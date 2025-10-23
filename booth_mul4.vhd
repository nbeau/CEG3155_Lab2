library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity booth_mul4 is
  port(
    clk   : in  std_logic;
    rst   : in  std_logic;
    start : in  std_logic;
    A_in  : in  std_logic_vector(3 downto 0);  -- multiplicand (signed)
    B_in  : in  std_logic_vector(3 downto 0);  -- multiplier   (signed)
    done  : out std_logic;
    P_out : out std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of booth_mul4 is
  type state_t is (S_IDLE, S_CHECK, S_OP, S_SHIFT, S_DEC, S_DONE);
  signal st, st_n : state_t;

  -- 工作寄存器
  signal A, A_n : std_logic_vector(3 downto 0);  -- accumulator
  signal Q, Q_n : std_logic_vector(3 downto 0);  -- multiplier
  signal M      : std_logic_vector(3 downto 0);  -- multiplicand (latched)
  signal Qm1, Qm1_n : std_logic;                 -- Q_-1
  signal cnt, cnt_n  : unsigned(2 downto 0);     -- 0..4

  -- 将“本次要加/减”的选择先寄存，下一拍使用，避免组合竞态
  signal op_sel_reg, op_sel_n : std_logic;       -- 0:add, 1:sub；仅在需要时有效
  signal do_op_reg,  do_op_n  : std_logic;       -- 1 表示这一轮需要执行 A←A±M

  -- 1-bit add/sub 组件
  component addsub_n is
    generic(N : integer := 4);
    port(
      A      : in  std_logic_vector(N-1 downto 0);
      B      : in  std_logic_vector(N-1 downto 0);
      AddSub : in  std_logic;  -- 0 add, 1 sub
      S      : out std_logic_vector(N-1 downto 0);
      Cout   : out std_logic;
      V_ovf  : out std_logic
    );
  end component;

  signal S_res : std_logic_vector(3 downto 0);
  signal dmy_c, dmy_v : std_logic;

  -- 算术右移 {A,Q,Qm1}
  function arith_right_shift(
    A_in : std_logic_vector(3 downto 0);
    Q_in : std_logic_vector(3 downto 0);
    Q1   : std_logic
  ) return std_logic_vector is
    variable res : std_logic_vector(8 downto 0);
    variable sgn : std_logic;
  begin
    res := A_in & Q_in & Q1;
    sgn := A_in(3);
    res := sgn & res(8 downto 1);
    return res;
  end function;
  signal bundle : std_logic_vector(8 downto 0);

begin
  -- 用“寄存的选择 op_sel_reg”驱动 add/sub，输出 S_res 供 OP 状态下一拍使用
  U_ADD: addsub_n
    generic map (N => 4)
    port map(
      A      => A,
      B      => M,
      AddSub => op_sel_reg,
      S      => S_res,
      Cout   => dmy_c,
      V_ovf  => dmy_v
    );

  ------------------------------------------------------------------
  -- 组合：下一状态与“下一拍要做什么”控制信号
  ------------------------------------------------------------------
  process(st, A, Q, Qm1, cnt, op_sel_reg, do_op_reg, S_res)
    variable qpair : std_logic_vector(1 downto 0);
  begin
    st_n       <= st;
    A_n        <= A;
    Q_n        <= Q;
    Qm1_n      <= Qm1;
    cnt_n      <= cnt;
    op_sel_n   <= op_sel_reg;
    do_op_n    <= '0';  -- 缺省认为本轮不做 A±M

    case st is
      when S_IDLE =>
        -- 等待时钟过程去装载
        null;

      when S_CHECK =>
        qpair := Q(0) & Qm1;
        if qpair = "10" then         -- A <- A - M
          op_sel_n <= '1'; do_op_n <= '1';
          st_n     <= S_OP;
        elsif qpair = "01" then      -- A <- A + M
          op_sel_n <= '0'; do_op_n <= '1';
          st_n     <= S_OP;
        else                         -- 无操作，直接移位
          st_n     <= S_SHIFT;
        end if;

      when S_OP =>
        -- 这一拍使用上拍寄存好的 op_sel_reg，S_res 已稳定
        if do_op_reg = '1' then
          A_n <= S_res;
        end if;
        st_n <= S_SHIFT;

      when S_SHIFT =>
        bundle  <= arith_right_shift(A, Q, Qm1);
        A_n     <= bundle(8 downto 5);
        Q_n     <= bundle(4 downto 1);
        Qm1_n   <= bundle(0);
        st_n    <= S_DEC;

      when S_DEC =>
        -- 做 4 次循环：cnt 从 4 递减到 1，减到 1 后转 DONE
        if cnt = 1 then
          st_n <= S_DONE;
        else
          cnt_n <= cnt - 1;
          st_n  <= S_CHECK;
        end if;

      when S_DONE =>
        st_n <= S_IDLE;
    end case;
  end process;

  ------------------------------------------------------------------
  -- 时序：装载、寄存控制、推进状态
  ------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        st        <= S_IDLE;
        A         <= (others => '0');
        Q         <= (others => '0');
        Qm1       <= '0';
        M         <= (others => '0');
        cnt       <= (others => '0');
        op_sel_reg<= '0';
        do_op_reg <= '0';
      else
        if (st = S_IDLE) and (start = '1') then
          -- 上升沿装载输入与计数
          A   <= (others => '0');
          Q   <= B_in;
          M   <= A_in;
          Qm1 <= '0';
          cnt <= to_unsigned(4, cnt'length);  -- 4 次
          st  <= S_CHECK;
          -- 本拍不做加/减，下一拍在 S_CHECK 里决定
          op_sel_reg <= '0';
          do_op_reg  <= '0';
        else
          st        <= st_n;
          A         <= A_n;
          Q         <= Q_n;
          Qm1       <= Qm1_n;
          cnt       <= cnt_n;
          op_sel_reg<= op_sel_n;
          do_op_reg <= do_op_n;
        end if;
      end if;
    end if;
  end process;

  done  <= '1' when st = S_DONE else '0';
  P_out <= A & Q;  -- 在 DONE 时即为最终积

end architecture;
