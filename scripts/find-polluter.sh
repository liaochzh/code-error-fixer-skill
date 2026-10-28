#!/usr/bin/env bash
# find-polluter.sh — 测试污染定位（三阶段）
#
# 为什么不是「逐个单跑，第一个非 0 就是元凶」：
#   目标场景是「全量失败、单跑通过」，单跑循环恒为 0 ⇒ 会误报「无污染」；
#   而当某用例自身就失败时，非 0 项是 victim，不是污染源。
#
# 三阶段：
#   1) --single  逐项单跑，报 VICTIM（自身失败项），先摘除它们
#   2) 默认模式  累积前缀（前 k 项），首个失败点记 BREAK_AT（这是被破坏者）
#   3) 收缩      在 BREAK_AT 之前逐项配对复现，报真正的 POLLUTER
#
# 退出码：0 全过 / 1 找到 / 2 参数错 / 3 harness 不可用
# 前提：项须按 runner 实际执行顺序给出；只覆盖累积型污染，
#       逆序 / 成对污染测不到，此时不得把 exit 0 读成「无污染」。
# 限制：模板按空白切 argv，模板内不得含带空格或引号的参数。
#       `{}` 必须是独立的一个 argv 元素（默认模式需要展开成多个项）。
set -u
set -f

usage() {
  printf '%s\n' \
    '用法: find-polluter.sh [--single] "<测试命令模板含 {}>" <项> [<项>...]' \
    '  --single  逐项单跑，报 VICTIM（自身失败项）' \
    '  默认      累积前缀定位 BREAK_AT，再收缩出 POLLUTER' \
    '示例: find-polluter.sh "npx jest {}" test/a.test.ts test/b.test.ts' \
    '退出码: 0 全过 / 1 找到 / 2 参数错 / 3 harness 不可用' >&2
  exit 2
}

[ $# -ge 2 ] || usage

MODE=prefix
if [ "${1:-}" = "--single" ]; then
  MODE=single
  shift
fi

[ $# -ge 2 ] || usage

TEMPLATE=$1
shift

ITEMS=("$@")
[ ${#ITEMS[@]} -gt 0 ] || usage

# 模板必须含 {}；默认模式要求 {} 是独立元素（要展开成多个项）
HAS_PLACEHOLDER=0
HAS_EXACT_PLACEHOLDER=0
for tok in $TEMPLATE; do
  case "$tok" in
    '{}') HAS_PLACEHOLDER=1; HAS_EXACT_PLACEHOLDER=1 ;;
    *'{}'*) HAS_PLACEHOLDER=1 ;;
  esac
done
[ "$HAS_PLACEHOLDER" = 1 ] || { echo 'ERROR: 模板缺少 {} 占位符' >&2; exit 2; }
if [ "$MODE" = prefix ] && [ "$HAS_EXACT_PLACEHOLDER" = 0 ]; then
  echo 'ERROR: 默认模式要求模板中的 {} 是独立参数元素（如 "pytest {}"），否则无法展开成多个项' >&2
  exit 2
fi

# 跑一次模板；成功返回 0。harness 不可用直接退出 3。
run_once() {
  local -a argv=()
  local tok out rc
  for tok in $TEMPLATE; do
    if [ "$tok" = '{}' ]; then
      argv+=("$@")
    else
      argv+=("$tok")
    fi
  done
  out=$("${argv[@]}" 2>&1)
  rc=$?
  if [ "$rc" -eq 127 ] || { [ "$rc" -ne 0 ] && printf '%s' "$out" | head -3 | grep -q 'No test suite found'; }; then
    printf '%s\n' "HARNESS_UNAVAILABLE: ${argv[*]}" >&2
    printf '%s\n' "$out" | head -5 >&2
    exit 3
  fi
  if [ "$rc" -ne 0 ]; then
    LAST_OUTPUT=$out
  fi
  return "$rc"
}

LAST_OUTPUT=''
N=${#ITEMS[@]}

if [ "$MODE" = single ]; then
  victims=0
  for ((i = 0; i < N; i++)); do
    if ! run_once "${ITEMS[i]}"; then
      echo "VICTIM: ${ITEMS[i]}"
      victims=$((victims + 1))
    fi
  done
  if [ "$victims" -gt 0 ]; then
    exit 1
  fi
  echo "OK: ${N} item(s) all pass standalone"
  exit 0
fi

for ((k = 1; k <= N; k++)); do
  if run_once "${ITEMS[@]:0:k}"; then
    continue
  fi

  break_item=${ITEMS[k - 1]}
  if [ "$k" -eq 1 ]; then
    echo "VICTIM: ${break_item}（自身失败，先用 --single 摘除后再定位污染）"
    exit 1
  fi

  echo "BREAK_AT: ${break_item}（被破坏者，不是元凶）"

  found=''
  for ((j = 0; j < k - 1; j++)); do
    if ! run_once "${ITEMS[j]}" "$break_item"; then
      found=${ITEMS[j]}
      break
    fi
  done

  if [ -n "$found" ]; then
    echo "POLLUTER: ${found}"
  else
    echo "POLLUTER: unresolved（需 ≥2 项共同作用，或依赖更长的执行顺序）"
  fi
  exit 1
done

echo "OK: no cumulative break in ${N} item(s)"
echo "NOTE: exit 0 仅代表该顺序下无累积型断点，不等于「无污染」" >&2
exit 0
