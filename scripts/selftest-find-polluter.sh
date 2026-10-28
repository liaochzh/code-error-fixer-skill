#!/usr/bin/env bash
# selftest-find-polluter.sh — find-polluter.sh 的回归自测（7 条，表驱动）
#
# 为什么落盘：样例原先只活在 $TMPDIR，会话一关就不可复核；「全绿」必须是别人能重跑的事实。
# 覆盖的判定分支：全过 / 单件自失败 / 前缀型污染命中单项 / 成对污染（unresolved）/ 参数错 / harness 不可用 / 模板缺占位符。
#
# 用法：bash scripts/selftest-find-polluter.sh   → 全过 rc=0，任一失败 rc=1
set -u
set -f

HERE=$(cd "$(dirname "$0")" && pwd)
FP="$HERE/find-polluter.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/cef-selftest.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

# ---- 夹具 ----
# harness 每次调用先清场：否则前缀轮残留的 flag 会让「配对收缩」阶段把单项误指成元凶。
cat > "$WORK/harness.sh" <<'SH'
d=$(cd "$(dirname "$0")" && pwd)
rm -f "$d"/flag_*
for f in "$@"; do bash "$d/$f" || exit 1; done
exit 0
SH

printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/ok_a.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/ok_b.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/victim.sh"

# 前缀型污染：单个造副作用，后一个依赖该副作用
printf '#!/usr/bin/env bash\n: > "$(dirname "$0")/flag_p"\nexit 0\n' > "$WORK/p_polluter.sh"
printf '#!/usr/bin/env bash\nd=$(dirname "$0")\n[ -f "$d/flag_p" ] && exit 1\nexit 0\n' > "$WORK/p_victim.sh"

# 成对污染：任一单项都不足以致污，两者同时出现才失败 ⇒ 收缩阶段必然落空
printf '#!/usr/bin/env bash\n: > "$(dirname "$0")/flag_A"\nexit 0\n' > "$WORK/pair_a.sh"
printf '#!/usr/bin/env bash\n: > "$(dirname "$0")/flag_C"\nexit 0\n' > "$WORK/pair_c.sh"
printf '#!/usr/bin/env bash\nd=$(dirname "$0")\n[ -f "$d/flag_A" ] && [ -f "$d/flag_C" ] && exit 1\nexit 0\n' > "$WORK/pair_victim.sh"

TPL="bash $WORK/harness.sh {}"

PASS=0
FAIL=0
OUT=''
RC=0

report() { # $1=label $2=ok?
  if [ "$2" = 1 ]; then
    PASS=$((PASS + 1))
    printf '  ok   %s\n' "$1"
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL %s\n' "$1"
    printf '%s\n' "$OUT" | sed 's/^/       | /'
    printf '       rc=%s\n' "$RC"
  fi
}

has_all() { # 每个 token 都必须出现在 $OUT 里
  local t
  for t in "$@"; do
    case "$OUT" in
      *"$t"*) ;;
      *) return 1 ;;
    esac
  done
  return 0
}

echo "fixtures: $WORK"
echo "sut: $FP"
echo

# 1 全过
OUT=$("$FP" "$TPL" ok_a.sh ok_b.sh 2>&1); RC=$?
[ "$RC" = 0 ] && has_all 'no cumulative break' && R=1 || R=0
report "1 全过（rc=0 + 提示不等于无污染）" "$R"

# 2 单件自失败
OUT=$("$FP" --single "$TPL" ok_a.sh victim.sh 2>&1); RC=$?
[ "$RC" = 1 ] && has_all 'VICTIM: victim.sh' && R=1 || R=0
report "2 单件自失败（--single 报 VICTIM）" "$R"

# 3 前缀型污染：应定位到造副作用的那一项
OUT=$("$FP" "$TPL" p_polluter.sh p_victim.sh 2>&1); RC=$?
[ "$RC" = 1 ] && has_all 'BREAK_AT: p_victim.sh' 'POLLUTER: p_polluter.sh' && R=1 || R=0
report "3 前缀型污染（BREAK_AT + POLLUTER）" "$R"

# 4 缺参数
OUT=$("$FP" "$TPL" 2>&1); RC=$?
[ "$RC" = 2 ] && has_all '用法:' && R=1 || R=0
report "4 缺参数（rc=2）" "$R"

# 5 harness 不可用
OUT=$("$FP" 'definitely-no-such-cmd {}' ok_a.sh 2>&1); RC=$?
[ "$RC" = 3 ] && has_all 'HARNESS_UNAVAILABLE' && R=1 || R=0
report "5 harness 不可用（rc=3）" "$R"

# 6 模板缺占位符
OUT=$("$FP" 'bash harness.sh' ok_a.sh 2>&1); RC=$?
[ "$RC" = 2 ] && has_all '缺少 {}' && R=1 || R=0
report "6 模板缺占位符（rc=2）" "$R"

# 7 成对污染：单项配对都过 ⇒ 必须报 unresolved，不得硬指元凶
OUT=$("$FP" "$TPL" pair_a.sh pair_c.sh pair_victim.sh 2>&1); RC=$?
[ "$RC" = 1 ] && has_all 'BREAK_AT: pair_victim.sh' 'POLLUTER: unresolved' && R=1 || R=0
report "7 成对污染（POLLUTER: unresolved）" "$R"

echo
echo "结果：$PASS 通过 / $FAIL 失败（共 7 条）"
[ "$FAIL" = 0 ] || exit 1
exit 0
