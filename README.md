# code-error-fixer

一个用于 **编译/运行报错与异常** 的 agent skill：把「看到报错 → 猜着改 → 又冒新错」变成五步闭环（复现 → 定位 → 理解 → 修复 → 验证），并且**没有根因就不改代码**。

> 面向 opencode / Claude 一类支持 `SKILL.md` 的 agent 运行时。纯提示词 + 3 个只读脚本，无外部依赖、不联网。

## 它解决什么问题

| 常见失败 | 本 skill 的做法 |
|---|---|
| 报错没看全就开始改 | Step 1 强制收集完整错误信息与复现条件；禁止「应该 / 看起来」代替命令输出 |
| 一次改五个地方，不知道哪个起了作用 | 禁止霰弹式修改；一次只改一个可验证的假设 |
| 「这段代码在某种输入下会走进来」被当成根因 | 明确判据：**条件式成立 ≠ 根因**，必须给出「原失败路径 → 该分支 → 现象」的完整复现链 |
| 连续修不好还在加补丁 | 升级阶梯：2 轮不成立质疑假设，≥3 次失败质疑架构并上报 |
| 用 `try/catch`、默认值、加大 sleep 掩盖症状 | 禁止清单直接拦截；防御层只在根因修好后加 |
| 权限被拒就整段交回，放弃诊断 | 角色边界按**白名单**分叉：白名单内换等价只读做法（`glob` / `read`），白名单外交回有写权限的角色 |

## 何时触发

报告编译错误、运行时异常、类型错误、逻辑 Bug、崩溃堆栈、依赖解析失败，或直接问「为什么不工作 / 修复这个错误 / 调试这个」时。

**不适用于**：实施前的方案/设计文档评审（用 `design-review`）、真机复现取证（用 `debug-loop` / `autoDebug`）、目标位置未知的多轮定位（用 `progressive-find`）。`description` 里已写明这些排除关系。

## 安装

```bash
# 方式一：整个目录放到 skills 根目录
git clone https://github.com/liaochzh/code-error-fixer-skill.git
cp -R code-error-fixer-skill ~/.config/opencode/skills/code-error-fixer

# 方式二：软链（便于跟随仓库更新）
git clone https://github.com/liaochzh/code-error-fixer-skill.git ~/Projects/code-error-fixer-skill
ln -s ~/Projects/code-error-fixer-skill ~/.config/opencode/skills/code-error-fixer
```

若用 Claude Code，把目录放到对应 skills 根目录即可，`SKILL.md` 格式通用。

## 结构

```
SKILL.md                          # 五步工作流 + 角色 A/B 分工 + 禁止清单（338 行）
references/
  root-cause-tracing.md           # 逆向追溯、分层插桩、收缩定位（二分 / 逐项配对）
  defense-in-depth.md             # 根因修好后的四层防御，以及不该加防御的场景
  async-and-flaky.md              # 条件等待替代 sleep、间歇性 bug 取证
scripts/
  find-polluter.sh                # 三阶段测试污染定位：摘 victim → 前缀断点 → 逐项配对
  validate-skills.py              # skill 目录结构自检（只读，不进 CI 门禁）
  selftest-find-polluter.sh       # 7 条表驱动回归
  selftest-validate-skills.sh     # 11 条表驱动回归 + --mutation 变异测试
```

references 刻意保持**一层深**：`SKILL.md` 只直接链接三份文档，避免「第二跳才能到达」的隐藏依赖。

## 自测

```bash
bash scripts/selftest-find-polluter.sh        # 7 条 → rc=0
bash scripts/selftest-validate-skills.sh      # 11 条 → rc=0
bash scripts/selftest-validate-skills.sh --mutation   # 打断被测脚本，应恰好报出用例 5 / 8
```

`--mutation` 是这套自测的**反证**：把 `validate-skills.py` 复制一份并打两处变异（规则 6 报错 token 失效、正文阈值 500→600），再让自测指向该副本。若仍然全绿，说明断言写宽了。改这两个脚本前请先跑对应自测——这是 `SKILL.md` 禁止清单里的第 11 条。

## 设计取舍

- **判据优先于散文**：每条约束写成可机械判读的判据（含反例），而不是「建议注意」。
- **不新增章节**：新约束并入既有 Step；正文控制在 400 行预警线内，细节拆 `references/`。
- **脚本只读**：`find-polluter.sh` 只跑用例、`validate-skills.py` 只读目录，都不修改被测项目。
- **约束可追溯**：每条判据都能指到具体证据（评测轮次或复盘记录），不接受「凭感觉加的规则」。

## 许可

MIT，见 [LICENSE](LICENSE)。
