# 逆向追溯与插桩取证

> 何时读：报错点在调用链深处、值从远处传来、错误静默（无异常但结果错）、或需要找出「哪个用例/哪次提交引入了问题」。

## 一、逆向追溯五步

```text
现象 → 直接原因 → 谁调用了它（带什么值） → 继续向上 → 找到最初来源
```

1. **观察现象**：拿到确切的错误与位置（堆栈首帧 / 错误日志行）。
2. **找直接原因**：哪一行代码直接产生了这个错误？
3. **问「谁传进来的」**：调用者是谁？传了什么值？在什么状态下调用？
4. **继续向上**：每上一层记录「入参 / 返回 / 关键状态」，直到找到**值的来源**。
5. **在源头修**，不在报错点兜。报错点只是症状的观测面。

**判定「到源头了」**：此处再往上是外部输入（用户输入、网络、配置、时间、随机数），或此处已能说明「为什么会是空 / 为什么顺序错了」。

**反模式**：在抛错处加 `try/catch`、给参数补 `?? 默认值`、给调用方加 `if (x)` —— 都是把观测面当成了病灶。

## 二、插桩规范

插桩是为了**取得可复核的事实**，必须可一次性干净移除。

### 命名与标记

- 统一前缀：`[DBG]`（便于 `grep -n "\[DBG\]"` 定位与清理）。
- 整块用 region 标记包裹，便于整段删除：

```js
// #region DEBUG
console.error('[DBG] createSession input', { projectDir, cwd: process.cwd() });
// #endregion DEBUG
```

```python
# #region DEBUG
print("[DBG] resolve() ->", repr(path), file=sys.stderr)
# #endregion DEBUG
```

```html
<!-- #region DEBUG -->
<!-- #endregion DEBUG -->
```

### 记录什么

| 记录项 | 为什么 |
|---|---|
| 进 / 出的值（含类型） | 定位「值在哪一层变质」 |
| 关键分支的实际走向 | 区分「没进入分支」与「进入后逻辑错」 |
| 时间戳 / 序号（并发） | 判断交错顺序与超时 |
| 关联 ID（请求 ID / 会话 ID） | 多请求并发时把日志串成一条链 |
| 环境上下文（cwd、env、版本） | 排除环境差异 |

### 输出通道

- 优先写**专用日志文件**（如项目根的 `.debug/debug.log`，追加写），避免污染 stdout 干扰测试断言与输出解析。
- 测试环境可用 `console.error` / `stderr`，但要保证可 grep。
- 每次复现前**归档**旧日志（`debug.log` → `debug-1.log` 递增），保证本次日志只含本次运行。

### 回读纪律（省 token）

```bash
wc -l .debug/debug.log            # 先看规模
grep "\[DBG\]" .debug/debug.log | tail -50
grep "\[DBG H2\]" .debug/debug.log   # 按假设编号过滤
```

不要整段读回大日志；先过滤再读。

### 清理

验证通过后：grep 标记 → 删除插桩块 → 删除日志与一次性脚本 → 确认 diff 无残留。

## 三、收缩定位（二分 / 逐项配对）

| 维度 | 做法 |
|---|---|
| 代码二分 | 注释 / 开关掉一半代码，确认错误是否消失，重复收敛到最小片段 |
| 输入二分 | 把输入对半裁掉，保留仍能触发的那半，直到最小触发数据 |
| 提交二分 | `git bisect start` → `git bisect good <old>` → `git bisect bad HEAD` → `git bisect run <复现命令>`（`debug` 档 shell 白名单外，交角色 B） |
| 测试污染收缩 | 全量失败、单跑通过 ⇒ 三阶段：摘 victim → 前缀定位断点 → 逐项配对收缩致污项（不复现则 `unresolved`） |

测试污染三阶段（脚本 `scripts/find-polluter.sh`，**由角色 B / 主 agent 执行**；`debug` 档 shell 白名单外）：

```bash
# 1) 摘除「自身就失败」的用例（这些是 victim，不参与归因）
scripts/find-polluter.sh --single "npx jest {}" $(npx jest --listTests)

# 2) 累积前缀：找到第一个把整批跑挂的断开点（BREAK_AT = 被破坏者，不是元凶）
scripts/find-polluter.sh "npx jest {}" test/a.test.ts test/b.test.ts test/c.test.ts

# 3) 脚本在断开点前逐项与 BREAK_AT 配对复现（线性扫描），输出 POLLUTER
#    若任何单项配对都不复现 ⇒ 输出 POLLUTER: unresolved（需 ≥2 项共同作用），交人工按组合复现
```

手工等价做法：按 runner **实际执行顺序**排列用例；第 k 项首次触发失败 ⇒ 它是被破坏者，元凶在前 k−1 项内；把前 k−1 项**逐项**与第 k 项配对跑，第一个「去掉它就不再失败」的那一项就是元凶；若逐项都不成立，说明是**组合型污染**（≥2 项共同作用），不要硬指单项。

**不要**用「逐个单跑，第一个非 0 就是元凶」：单跑全过时该循环恒为 0（会误报「无污染」），非 0 时报的是自身失败项（victim）。

**判断要点**：单跑通过、全量失败 ⇒ 状态污染（全局变量、单例、临时目录、端口、数据库、时区、环境变量），不是「测试框架不稳定」。

## 四、常见判断错误

- 只看错误最后一行 ⇒ 丢掉真正的首因；要从**最早的**错误看起。
- 只加日志不清理 ⇒ 下次排查时日志互相污染，也让 diff 不可信。
- 日志打 stdout ⇒ 被断言/管道吞掉，或在 CI 里丢失。
- 采信「复现不了但应该是 X」⇒ 未复现就是证据不足。

---

出处：思路参考 `obra/superpowers`（MIT）的 systematic-debugging / root-cause-tracing，与 `doraemonkeys/claude-code-debug-mode`（MIT）的插桩与日志规范，按本环境改写。
