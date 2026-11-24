# 接力棒：code-error-fixer skill（2026-10-27）

## 模块边界

只做「编译/运行报错与异常的诊断 + 修复」，边界写死在 `description` 的「不用于」里（不用于方案评审、不用于真机复现取证、不用于目标位置未知的多轮定位）。

| 层 | 文件 |
|---|---|
| 正文 | `~/.config/opencode/skills/code-error-fixer/SKILL.md`（五步法 + 角色 A/B 分工） |
| references（一层深） | `references/root-cause-tracing.md`、`references/defense-in-depth.md`、`references/async-and-flaky.md` |
| 脚本 | `scripts/find-polluter.sh`（三阶段污染定位）、`scripts/validate-skills.py`（结构自检）、`scripts/selftest-find-polluter.sh`（7 条回归）、`scripts/selftest-validate-skills.sh`（11 条回归 + `--mutation` 变异测试） |
| 对标留痕 | `~/.config/opencode/references/code-error-fixer-open-source.md`（含「v4 回采」三条判据及证据轮次；不属于本仓库） |
| 仓库 | `~/Projects/code-error-fixer-skill` → https://github.com/liaochzh/code-error-fixer-skill （**public**，MIT）。`~/.config/opencode/skills/code-error-fixer` 是**目录级软链**指向该仓库；`docs/` 被 `.gitignore` 排除，只留本地 |
| 方案/评测（本地，未发布） | 已归档：`docs/archive/2026-11-收口与能力验收.md`（原 `docs/plan/20261027-code-error-fixer-next.md` §10 = v5、`docs/test/20261027-code-error-fixer-eval.md` §5.12–§5.15 的结论已并入该档） |

`debug` agent 加载时只跑 Step 1–3（角色 A，`edit *` deny、`shell *` deny + 白名单）；`build` 跑 Step 4–5（角色 B）。

## 当前版本

- `SKILL.md`：**338 行**，sha256 `01de681f5cb210cfa7a8fd975556c914c6b4548e89c3a47ec377da0bb9a6bb44`（v5.3：禁止事项清单 +1 条「改脚本必跑自测」、延伸阅读措辞同步）。
  评测读数（E2/E6）是在 **337 行 / `f23c93ec637e6e044586c4b743b0ae4461d412c633ae27521c2fd8a05057b467`** 上取的，引用评测结论时按该哈希对照，别与当前版本混读。
- 自测：`bash scripts/selftest-find-polluter.sh` → **7 通过 / 0 失败，rc=0**（TMPDIR 临时夹具，退出即清理）。
- 自测：`bash scripts/selftest-validate-skills.sh` → **11 通过 / 0 失败，rc=0**；`--mutation` → 变异体上恰好检出用例 5 / 8，**rc=0**（证明用例有对症性，不是空转）。
- 结构自检：`python3 scripts/validate-skills.py` → **FAIL 0 / WARN 1**（WARN 来自 `clean-code` 497 行超 400，与本 skill 无关）。
- 门禁：`python3 ~/.config/opencode/scripts/verify-env-guard.py --gate --quiet` → rc=0。
- 改前基线留档：`~/.config/opencode/.backups/20261027-v4/`（两份 SKILL.md + 哈希 + E2 旧 fixture）。

## 三条铁律（改这个 skill 时不许绕过）

1. **证据门**：无根因不写修复；Step 5 每条结论须能指到「命令 + 输出片段」，不接受「应该没问题」。
2. **条件式成立 ≠ 根因**：证明某分支「条件可成立」只排除了不可达，不构成根因；须给出「原失败路径 → 该分支 → 现象」的完整复现链（E2 第 3 次派发逼出来的判据）。
3. **权限拒因按白名单分叉**：先看目标命令是否在 `debug` 档白名单内，再决定「交角色 B」还是「改走等价只读命令」（拆单条 / 用 `glob`、`read` 替代 shell 探路），不是「被拒就上抛」（E5 证据）。

## 踩过的坑

- **复合命令拒因误判**：`cd x && cmd`、`set -u` 起头的命令在 `debug` 档必然 deny，与「命令本身不可用」是两回事；夹具/自测一律写成脚本文件再 `bash <绝对路径>`。
- **fixture 同源泄漏**：`e2-v1/` 曾作为被测目录的兄弟目录存在，模型能顺路读到「标准答案」；现改为归档进 `.backups/`。同理，被测夹具不要放在被测目录的同级可 grep 到的位置。
- **作者自评无判别力**：自己造的夹具自己判，只会确认自己想看的；验收一律「派发即盲测」，不看自检清单。E2 四轮 `R3/R4` = 0/1、0/1、1/0 就是证据——单轮读数不能当结论。**自测脚本同理**：`selftest-validate-skills.sh --mutation` 每次把 SUT 打断再跑自己，期望恰好检出用例 5 / 8；没有这一步，「11/11 全绿」可能只是断言写宽了。
- **收缩是线性不是二分**：`find-polluter.sh` 只做「单项 + `BREAK_AT`」配对，成对污染必然落 `POLLUTER: unresolved`（`:128`），此时不要硬指元凶，交人工按 ≥2 项组合复现。
- **validate-skills 两套解析基准**：`SKILL.md` 内链接相对 skill 目录，被引文档内链接相对该文档所在目录；在 `references/a.md` 里写 `references/sub/b.md` 会被拼成 `references/references/…` 而静默跳过（探针因此假阴性过）。
- **规划档写不进 `docs/plan/`**：`Plan`/`planner` 差异见全局规则；本轮 v5.1 就是因落在 planner 态无法跑 shell 而整体交回 build。

## 未完成项

- `clean-code/SKILL.md` 497 行仍触发 `validate-skills.py` 的 WARN（阈值 400）；已拆出 `references/solid-and-architecture.md`，二次拆分未做（用户裁定保留 WARN）。
- E2 的 R4 维度已移交 E6，但 E6 的 ④ 只有 **n=1** 观测；要升级为硬覆盖需再跑 2–3 轮，否则 R4 硬线仍只由 E5 承载。
- `validate-skills.py` 规则 6 的 FAIL 侧已由 `selftest-validate-skills.sh` 覆盖（11 条 + `--mutation`）；遗留：该脚本**未接入门禁**（刻意，见 `validate-skills.py` 头注释「不接入 `--gate`」），需手动跑。
- `debug-loop`、`design-review`、`product-prototype-generation` 的 `description` 曾被外部改动（正文本轮核实未被动）；跨 skill 口径漂移无人守，需在下次改动时复核。
