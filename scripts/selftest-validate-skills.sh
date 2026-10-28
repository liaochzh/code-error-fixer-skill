#!/usr/bin/env bash
# selftest-validate-skills.sh — validate-skills.py 的回归自测（11 条，表驱动）
#
# 为什么落盘：validate-skills.py 的 FAIL 侧在本仓长期只有「无 FAIL 的 happy path」一条读数
# （12 个 skill 全绿），规则 1–6 的报错分支从未被执行过 —— 判据写错、路径基准写错都会静默通过。
# 本脚本用临时 skills-dir 逐条构造正例/反例，把「哪条规则真的会报」变成可复核事实。
#
# 覆盖：合规骨架 / 规则1 name / 规则2 description 缺失 / 规则3 description 超长 /
#       规则4 正文超长 / 规则5 引用不存在 / 规则5 目录外 INFO / 规则6 正例（深度>1）/
#       规则6 反例（直接引用去重）/ 行内代码不算引用 / 未找到 SKILL.md（rc=2）
#
# 相对路径基准（写夹具时必须遵守，否则条目会静默跳过而假阴性）：
#   SKILL.md 内的链接 → 相对 skill 目录
#   被引用文档内的链接 → 相对该文档所在目录
#
# 用法：bash scripts/selftest-validate-skills.sh              → 全过 rc=0，任一失败 rc=1
#       bash scripts/selftest-validate-skills.sh --mutation  → 变异测试：把 SUT 打断后重跑自身，
#                                                              期望恰好检出用例 5 / 8（证明用例不是空转）
set -u
set -f

HERE=$(cd "$(dirname "$0")" && pwd)
# SUT 可替换：默认测同目录脚本；变异模式下由本脚本自己注入坏副本
V=${VS_SUT:-$HERE/validate-skills.py}

# ---- 变异模式（必须用默认 SUT，否则变异的不是被测物）----
if [ "${1:-}" = "--mutation" ]; then
  if [ -n "${VS_SUT:-}" ]; then
    echo "--mutation 不接受 VS_SUT 预设（会变异错对象）" >&2
    exit 2
  fi
  STD=$(mktemp -d "${TMPDIR:-/tmp}/vs-mutant.XXXXXX") || exit 1
  ST="$STD/validate-skills.py"
  trap 'rm -rf "$STD"' EXIT
  # 变异 1：规则 6 的报错 token 失效；变异 2：规则 4 阈值 500 → 600
  sed -e 's/引用深度 > 1（只能经第二跳到达）/MUTATED_DEPTH_TOKEN/' \
      -e 's/^BODY_MAX = 500$/BODY_MAX = 600/' "$V" > "$ST"
  if ! grep -q 'MUTATED_DEPTH_TOKEN' "$ST" || ! grep -q '^BODY_MAX = 600$' "$ST"; then
    echo "变异点未生效（SUT 结构变了，请同步本脚本的 sed 锚点）" >&2
    exit 1
  fi
  echo "== 变异体：$ST =="
  MOUT=$(VS_SUT="$ST" bash "$0" 2>&1); MRC=$?
  printf '%s\n' "$MOUT" | grep -E '^  (ok|FAIL) |^结果：|^rc=' || true
  MFAILS=$(printf '%s\n' "$MOUT" | grep -c '^  FAIL ')
  echo
  if [ "$MRC" = 1 ] && [ "$MFAILS" = 2 ] \
     && printf '%s' "$MOUT" | grep -q '^  FAIL 5 ' \
     && printf '%s' "$MOUT" | grep -q '^  FAIL 8 '; then
    echo "变异测试 ok（恰好检出用例 5 / 8，其余 9 条不受影响）"
    exit 0
  fi
  echo "变异测试 FAIL（对症性不足：FAIL 数=$MFAILS，rc=$MRC）" >&2
  exit 1
fi
WORK=$(mktemp -d "${TMPDIR:-/tmp}/vs-selftest.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
OUT=''
RC=0

# 造一个「骨架合规」的 skill：name = 目录名、description 非空、正文短、无悬空链接
mk_skill() { # $1=case 名 $2=skill 目录名
  local d="$WORK/$1/$2"
  mkdir -p "$d"
  printf -- '---\nname: %s\ndescription: selftest fixture for validate-skills\n---\n\n# %s\n\n正文。\n' \
    "$2" "$2" > "$d/SKILL.md"
  printf '%s' "$d"
}

has() { case "$OUT" in *"$1"*) return 0 ;; *) return 1 ;; esac; }
hasnt() { case "$OUT" in *"$1"*) return 1 ;; *) return 0 ;; esac; }

report() { # $1=label $2=1/0
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

run() { # $1=root（输出写进 OUT / RC）
  OUT=$(python3 "$V" --skills-dir "$1" 2>&1)
  RC=$?
}

echo "fixtures: $WORK"
echo "sut: $V"
echo

# 1 合规骨架（对照组：证明夹具本身不产生噪声 FAIL）
D=$(mk_skill ok ok); run "$WORK/ok"
[ "$RC" = 0 ] && has 'FAIL 0' && R=1 || R=0
report "1 合规骨架（rc=0 / FAIL 0）" "$R"

# 2 规则 1：name 与目录名不一致
D=$(mk_skill name-mismatch real_name)
printf -- '---\nname: other_name\ndescription: selftest fixture for validate-skills\n---\n\n# x\n' > "$D/SKILL.md"
run "$WORK/name-mismatch"
[ "$RC" = 1 ] && has '与目录名 `real_name` 不一致' && R=1 || R=0
report "2 规则1 name 与目录名不一致（rc=1）" "$R"

# 3 规则 2：缺 description
D=$(mk_skill no-desc no_desc)
printf -- '---\nname: no_desc\n---\n\n# x\n' > "$D/SKILL.md"
run "$WORK/no-desc"
[ "$RC" = 1 ] && has 'frontmatter 缺 `description`' && R=1 || R=0
report "3 规则2 缺 description（rc=1）" "$R"

# 4 规则 3：description 超 1024
D=$(mk_skill long-desc long_desc)
LONG=$(printf 'x%.0s' $(seq 1 1025))
printf -- '---\nname: long_desc\ndescription: %s\n---\n\n# x\n' "$LONG" > "$D/SKILL.md"
run "$WORK/long-desc"
[ "$RC" = 1 ] && has 'description 1025 字 > 1024' && R=1 || R=0
report "4 规则3 description 超长（rc=1）" "$R"

# 5 规则 4：正文超 500 行
D=$(mk_skill long-body long_body)
{
  printf -- '---\nname: long_body\ndescription: selftest fixture for validate-skills\n---\n\n'
  for i in $(seq 1 520); do printf 'line %s\n' "$i"; done
} > "$D/SKILL.md"
run "$WORK/long-body"
[ "$RC" = 1 ] && has '行 > 500' && R=1 || R=0
report "5 规则4 正文超长（rc=1）" "$R"

# 6 规则 5：引用不存在
D=$(mk_skill missing-ref missing_ref)
printf -- '---\nname: missing_ref\ndescription: selftest fixture for validate-skills\n---\n\n# x\n\n见 [a](references/nope.md)。\n' > "$D/SKILL.md"
run "$WORK/missing-ref"
[ "$RC" = 1 ] && has '引用不存在：references/nope.md' && R=1 || R=0
report "6 规则5 引用不存在（rc=1）" "$R"

# 7 规则 5：指向 skill 目录外 ⇒ INFO，不判 FAIL
D=$(mk_skill outside-link outside_link)
printf -- '---\nname: outside_link\ndescription: selftest fixture for validate-skills\n---\n\n# x\n\n见 [o](../../shared/other.md)。\n' > "$D/SKILL.md"
run "$WORK/outside-link"
[ "$RC" = 0 ] && has '链接指向 skill 目录外，不校验' && R=1 || R=0
report "7 规则5 目录外链接记 INFO（rc=0）" "$R"

# 8 规则 6 正例：b 只能经第二跳到达 ⇒ FAIL
D=$(mk_skill depth-fail depth_fail)
mkdir -p "$D/references/sub"
printf -- '---\nname: depth_fail\ndescription: selftest fixture for validate-skills\n---\n\n# x\n\n见 [a](references/a.md)。\n' > "$D/SKILL.md"
printf '# a\n\n见 [b](sub/b.md)。\n' > "$D/references/a.md"
printf '# b\n\n叶子。\n' > "$D/references/sub/b.md"
run "$WORK/depth-fail"
[ "$RC" = 1 ] && has '引用深度 > 1（只能经第二跳到达）' && R=1 || R=0
report "8 规则6 正例：嵌套引用（rc=1）" "$R"

# 9 规则 6 反例：b 同时被 SKILL.md 直接引用 ⇒ 不报深度
D=$(mk_skill depth-ok depth_ok)
mkdir -p "$D/references/sub"
printf -- '---\nname: depth_ok\ndescription: selftest fixture for validate-skills\n---\n\n# x\n\n见 [a](references/a.md) 与 [b](references/sub/b.md)。\n' > "$D/SKILL.md"
printf '# a\n\n见 [b](sub/b.md)。\n' > "$D/references/a.md"
printf '# b\n\n叶子。\n' > "$D/references/sub/b.md"
run "$WORK/depth-ok"
[ "$RC" = 0 ] && hasnt '引用深度 > 1' && R=1 || R=0
report "9 规则6 反例：直接引用集去重（rc=0）" "$R"

# 10 行内代码里的文件名是「提及」不是「引用」⇒ 不校验、不报错
D=$(mk_skill inline-code inline_code)
printf -- '---\nname: inline_code\ndescription: selftest fixture for validate-skills\n---\n\n# x\n\n细节见 `references/nope.md`（提及，非链接）。\n' > "$D/SKILL.md"
run "$WORK/inline-code"
[ "$RC" = 0 ] && hasnt '引用不存在' && R=1 || R=0
report "10 行内代码不算引用（rc=0）" "$R"

# 11 未找到任何 SKILL.md ⇒ fail-closed rc=2
mkdir -p "$WORK/empty/not_a_skill"
run "$WORK/empty"
[ "$RC" = 2 ] && has '未找到任何' && R=1 || R=0
report "11 未找到 SKILL.md（rc=2，fail-closed）" "$R"

echo
echo "结果：$PASS 通过 / $FAIL 失败（共 11 条）"
[ "$FAIL" = 0 ] || exit 1
exit 0
