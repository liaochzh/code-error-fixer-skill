# 异步、超时与间歇性 Bug

> 何时读：测试偶发失败、只在 CI / 负载高时失败、并发下偶现、或用固定 `sleep` 等待结果。

## 一、固定等待是 bug 制造机

```ts
// ❌ 猜时间：快机器过、慢机器挂
await new Promise(r => setTimeout(r, 50));
expect(getResult()).toBeDefined();

// ✅ 等条件
await waitFor(() => getResult() !== undefined);
expect(getResult()).toBeDefined();
```

```python
# ❌
time.sleep(0.2)
assert job.done
# ✅
wait_until(lambda: job.done, "job.done", timeout=5)
```

```dart
// ❌
await Future.delayed(const Duration(milliseconds: 200));
// ✅
await untilTrue(() => controller.state == State.ready, timeout: const Duration(seconds: 5));
```

## 二、条件等待实现要点

1. **有界**：必须有超时，超时抛出含「在等什么 / 等了多久 / 最后观察到的值」的错误。
2. **轮询有间隔**：约 10ms 级，别 1ms 空转。
3. **每次取新值**：条件里调用 getter，不要在循环外缓存状态。
4. **条件可观测**：定位失败时要输出「等了什么 + 当前值」，否则 flaky 依旧不可诊断。

```ts
async function waitFor<T>(
  cond: () => T | null | undefined | false,
  desc: string,
  timeoutMs = 5000,
  intervalMs = 10,
): Promise<T> {
  const start = Date.now();
  for (;;) {
    const v = cond();
    if (v) return v;
    if (Date.now() - start > timeoutMs) {
      throw new Error(`timeout waiting for ${desc} after ${timeoutMs}ms`);
    }
    await new Promise(r => setTimeout(r, intervalMs));
  }
}
```

## 三、何时固定延时是合理的

仅当**测的就是时序行为**（debounce、节流间隔、重排窗口）时：

1. 先等触发条件成立；
2. 延时基于**已知**的时序参数（如 2 个 100ms tick ⇒ 200ms），不是拍脑袋；
3. 代码里注释说明为什么是这个值。

## 四、间歇性 Bug 的取证

| 步骤 | 做法 |
|---|---|
| 记录稳定度 | 先量化：跑 N 次挂几次（`--repeat` / 循环脚本），不是「有时候会挂」 |
| 保留插桩 | 间歇问题不要撤日志，等下次触发；日志写文件并归档 |
| 串时间线 | 每条日志带时间戳 + 请求/会话 ID，还原执行顺序 |
| 缩小并发 | 单线程 / 单请求是否仍复现？能区分「自身逻辑错」与「交错导致」 |
| 加压复现 | 提高并发、注入延迟、模拟慢 IO，把概率问题变成必现 |
| 排除装置 | 先自问：是不是测试环境（端口占用、共享临时目录、残留数据、时钟）导致的 |

## 五、常见误判

- 「加个 retry 就好了」⇒ 只是把概率降低了，根因还在；retry 只能用于**幂等 + 已知瞬态**场景，且要记录重试次数。
- 「超时时间调大」⇒ 掩盖了「为什么需要这么久」。先确认是真的慢，还是有死锁 / 无限等待。
- 「本地跑 100 次都过」⇒ 本地与 CI 的差异（核数、时序、locale、并行度）本身就是线索，去对比而不是宣布无罪。

---

出处：思路参考 `obra/superpowers`（MIT）的 condition-based-waiting，按本环境改写。
