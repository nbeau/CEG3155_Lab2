library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- 4-bit Signed Restoring Divider (向0截断)
entity nr_div4_signed is
  port(
    clk      : in  std_logic;
    rst      : in  std_logic;                      -- 同步高有效复位
    start    : in  std_logic;                      -- 单拍脉冲
    Dividend : in  std_logic_vector(3 downto 0);   -- 被除数(有符号, 2's complement)
    Divisor  : in  std_logic_vector(3 downto 0);   -- 除数(有符号, 2's complement)
    done     : out std_logic;
    Q_out    : out std_logic_vector(3 downto 0);   -- 商(有符号, 向0截断)
    R_out    : out std_logic_vector(3 downto 0);   -- 余数(有符号, 符号=Dividend)
    div0     : out std_logic                       -- 除零标志
  );
end entity;

architecture rtl of nr_div4_signed is

  -- 状态机
  type state_t is (S_IDLE, S_PREP, S_SHIFT, S_CHECK, S_DEC, S_SIGN, S_DONE);
  signal st, st_n : state_t;

  -- 寄存输入
  signal A_reg, A_reg_n : std_logic_vector(3 downto 0);
  signal B_reg, B_reg_n : std_logic_vector(3 downto 0);

  -- 符号位
  signal sA_reg, sA_reg_n : std_logic;
  signal sB_reg, sB_reg_n : std_logic;

  -- 迭代寄存器
  signal Q, Q_n : unsigned(3 downto 0);
  signal R, R_n : unsigned(4 downto 0);

  -- 保存“本轮左移后的R”以避免在S_CHECK里重复计算导致二次左移
  signal R_after_shift, R_after_shift_n : unsigned(4 downto 0);

  signal Mmag, Mmag_n : unsigned(3 downto 0);
  signal cnt, cnt_n   : unsigned(1 downto 0);

  -- 输出寄存
  signal Q_res, Q_res_n : std_logic_vector(3 downto 0);
  signal R_res, R_res_n : std_logic_vector(3 downto 0);
  signal div0_r, div0_n : std_logic;
  signal done_r, done_n : std_logic;

  -- 并行派生信号（组合）
  signal absA  : unsigned(3 downto 0);
  signal absB  : unsigned(3 downto 0);
  signal Mext  : unsigned(4 downto 0);
  signal R_try : unsigned(4 downto 0);

  -- 4位二补码取绝对值（返回无符号幅值）
  function abs4(x : std_logic_vector(3 downto 0)) return unsigned is
  begin
    if x(3) = '1' then
      return unsigned(not x) + 1;
    else
      return unsigned(x);
    end if;
  end function;

  -- 4位幅值加符号，返回二补码（u为幅值）
  function apply_sign(u : unsigned(3 downto 0); s : std_logic) return unsigned is
  begin
    if s = '1' then
      return unsigned(not std_logic_vector(u)) + 1; -- 取反加一
    else
      return u;
    end if;
  end function;

begin

  -- 并行派生：幅值、试减（注意：使用已经寄存的R_after_shift进行试减）
  absA <= abs4(A_reg);
  absB <= abs4(B_reg);
  Mext <= '0' & Mmag;
  R_try <= R_after_shift - Mext;

  -------------------------------------------------------------------------
  -- 时序过程
  -------------------------------------------------------------------------
  seq_proc : process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        st      <= S_IDLE;
        A_reg   <= (others => '0');
        B_reg   <= (others => '0');
        sA_reg  <= '0';
        sB_reg  <= '0';
        Q       <= (others => '0');
        R       <= (others => '0');
        R_after_shift <= (others => '0');
        Mmag    <= (others => '0');
        cnt     <= (others => '0');
        Q_res   <= (others => '0');
        R_res   <= (others => '0');
        div0_r  <= '0';
        done_r  <= '0';
      else
        st      <= st_n;
        A_reg   <= A_reg_n;
        B_reg   <= B_reg_n;
        sA_reg  <= sA_reg_n;
        sB_reg  <= sB_reg_n;
        Q       <= Q_n;
        R       <= R_n;
        R_after_shift <= R_after_shift_n;
        Mmag    <= Mmag_n;
        cnt     <= cnt_n;
        Q_res   <= Q_res_n;
        R_res   <= R_res_n;
        div0_r  <= div0_n;
        done_r  <= done_n;
      end if;
    end if;
  end process;

  -------------------------------------------------------------------------
  -- 组合过程
  -------------------------------------------------------------------------
  comb_proc : process(st, start, Dividend, Divisor,
                      A_reg, B_reg, sA_reg, sB_reg,
                      Q, R, R_after_shift, Mmag, cnt,
                      absA, absB, Mext, R_try)
    variable Qtmp : unsigned(3 downto 0);
    variable Rsh  : unsigned(4 downto 0);
  begin
    -- 默认保持
    st_n     <= st;
    A_reg_n  <= A_reg;
    B_reg_n  <= B_reg;
    sA_reg_n <= sA_reg;
    sB_reg_n <= sB_reg;
    Q_n      <= Q;
    R_n      <= R;
    R_after_shift_n <= R_after_shift;
    Mmag_n   <= Mmag;
    cnt_n    <= cnt;
    Q_res_n  <= Q_res;
    R_res_n  <= R_res;
    div0_n   <= div0_r;
    done_n   <= done_r;

    case st is
      when S_IDLE =>
        done_n <= '0';
        div0_n <= '0';
        if start = '1' then
          A_reg_n <= Dividend;
          B_reg_n <= Divisor;
          if Divisor = "0000" then
            div0_n  <= '1';
            Q_res_n <= (others => '0');
            R_res_n <= Dividend;
            done_n  <= '1';
            st_n    <= S_DONE;
          else
            st_n    <= S_PREP;
          end if;
        end if;

      when S_PREP =>
        sA_reg_n <= A_reg(3);
        sB_reg_n <= B_reg(3);
        Q_n      <= absA;
        R_n      <= (others => '0');
        R_after_shift_n <= (others => '0');
        Mmag_n   <= absB;
        cnt_n    <= "11";
        st_n     <= S_SHIFT;

      when S_SHIFT =>
        -- 先计算本轮左移后的R，并把它寄存到R_after_shift
        Rsh := unsigned( R(3 downto 0) & std_logic(Q(3)) );
        R_after_shift_n <= Rsh;
        R_n             <= Rsh;
        -- Q左移并清LSB，等待S_CHECK置位
        Q_n(3 downto 1) <= Q(2 downto 0);
        Q_n(0)          <= '0';
        st_n            <= S_CHECK;

      when S_CHECK =>
        if R_try(4) = '1' then          -- 负：恢复到本轮左移后的R
          R_n <= R_after_shift;
          Q_n <= Q;                      -- 维持Q0=0
        else                             -- 非负：接受试减并置Q0=1
          R_n   <= R_try;
          Qtmp  := Q;
          Qtmp(0) := '1';
          Q_n   <= Qtmp;
        end if;
        st_n <= S_DEC;

      when S_DEC =>
        if cnt = "00" then
          st_n <= S_SIGN;                -- 完成4次
        else
          cnt_n <= cnt - 1;
          st_n  <= S_SHIFT;
        end if;

      when S_SIGN =>
        -- 符号修正（向0截断）：商符号=sA xor sB；余数符号=sA
        Q_res_n <= std_logic_vector(apply_sign(Q, sA_reg xor sB_reg));
        R_res_n <= std_logic_vector(apply_sign(unsigned(R(3 downto 0)), sA_reg));
        done_n  <= '1';
        st_n    <= S_DONE;

      when S_DONE =>
        if start = '0' then
          st_n <= S_IDLE;
        else
          st_n <= S_DONE;
        end if;

      when others =>
        st_n <= S_IDLE;
    end case;
  end process;

  -- 输出
  done  <= done_r;
  div0  <= div0_r;
  Q_out <= Q_res;
  R_out <= R_res;

end architecture;
