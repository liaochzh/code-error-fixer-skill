#!/usr/bin/env python3
"""validate-skills.py — skill 目录结构自检（离线、只读、不进门禁）

为什么存在：门禁 `verify-env-guard.py` 只校验 skill 的 frontmatter `description`
（§5-S 时效性、§5-O 关键句唯一性），不校验 name 与目录是否同名、description 长度、
正文行数、引用文件是否存在、引用是否可达。本脚本补这一段空白。

边界（刻意不做的）：
  - 不复刻日期 / 流水表述检查 ⇒ owner 是门禁 §5-S / §5-M，双写会漂移；
  - 不接入 `--gate`：门禁面向「常驻注入面」的时效性，本脚本面向目录结构；
    本脚本判红不应阻断无关的权限类改动；
  - 只读：不改任何文件。

判定口径：
  - 「引用」只认 **markdown 链接** `[文本](相对路径.md)`；
    正文里的行内代码（如 `web.md`、`docs/prd.md`）视为**提及**而非引用，不校验
    —— 它们多为表格里的文件名、项目产出路径或全局路径，按引用判会大量误报。
  - 规则 1-4（frontmatter / name 同名 / 长度 / 行数）只作用于 `<root>/*/SKILL.md`。
  - 规则 5（引用存在）作用于 SKILL.md 的链接；指向 skill 目录外的链接记 INFO 不判。
  - 规则 6（引用可达）只报「只能经第二跳才能到达」的文档：被引用文档再链接的
    文档若**不在 SKILL.md 的直接引用集**内，才算深层引用；checklist 之间互链、
    回链 SKILL.md 均不判。

退出码：0 无 FAIL ｜ 1 有 FAIL ｜ 2 未找到任何 SKILL.md（fail-closed）
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

SKILLS_DIR_DEFAULT = Path.home() / ".config" / "opencode" / "skills"

# 阈值出处：1024 = agentskills.io 规范 description 上限；500 = Anthropic skill 写作最佳实践（正文行数）。
DESC_MAX = 1024
BODY_MAX = 500
DESC_WARN = 512  # 自定预警线
BODY_WARN = 400  # 自定预警线


def skill_desc_extract(text: str) -> str:
    """取 frontmatter 的 `description` 值（取不到返回 ""）。

    owner = 门禁脚本 `~/.config/opencode/scripts/verify-env-guard.py:2446-2477`：
    本函数是**复制体**，改任一侧必须同步另一侧（登记见
    `references/code-error-fixer-open-source.md`）。
    支持：单行值（含引号、含 `:`）、YAML 折叠/字面量标量多行值。
    """
    text = (text or "").lstrip("\ufeff")
    m = re.match(r"^---\s*\n(.*?)\n---", text, re.S)
    if not m:
        return ""
    fm = m.group(1)
    d = re.search(r"^description:[ \t]*(.*)$", fm, re.M)
    if not d:
        return ""
    val = d.group(1).strip()
    if val in (">", "|", ">-", "|-", ">+", "|+"):
        lines = []
        for ln in fm[d.end():].splitlines():
            if not ln.strip():
                lines.append("")
                continue
            if ln[:1] in (" ", "\t"):
                lines.append(ln.strip())
            else:
                break
        val = " ".join(x for x in lines if x).strip()
    elif len(val) >= 2 and val[0] == val[-1] and val[0] in ("'", '"'):
        val = val[1:-1]
    return val.strip()


def skill_name_extract(text: str) -> str:
    """取 frontmatter 的 `name` 值。复制体只覆盖 description，这里自行实现。"""
    text = (text or "").lstrip("\ufeff")
    m = re.match(r"^---\s*\n(.*?)\n---", text, re.S)
    if not m:
        return ""
    d = re.search(r"^name:[ \t]*(.+)$", m.group(1), re.M)
    if not d:
        return ""
    val = d.group(1).strip()
    if len(val) >= 2 and val[0] == val[-1] and val[0] in ("'", '"'):
        val = val[1:-1]
    return val.strip()


LINK_RE = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")


def md_links(text: str) -> list[str]:
    """抽取 markdown 链接里的 `.md` 相对路径（去重、保序；跳过外链与纯锚点）。"""
    refs: list[str] = []
    seen: set[str] = set()
    for m in LINK_RE.finditer(text):
        target = m.group(1).split("#", 1)[0].strip()
        if not target.endswith(".md"):
            continue
        if target.startswith(("http://", "https://", "mailto:", "/")):
            continue
        if target not in seen:
            seen.add(target)
            refs.append(target)
    return refs


def resolve(base: Path, ref: str) -> Path:
    return (base / ref).resolve()


def in_dir(path: Path, directory: Path) -> bool:
    try:
        path.relative_to(directory.resolve())
        return True
    except ValueError:
        return False


def check_skill(skill_md: Path) -> tuple[list[str], list[str], list[str]]:
    fails: list[str] = []
    warns: list[str] = []
    infos: list[str] = []
    label = str(skill_md)
    try:
        text = skill_md.read_text(encoding="utf-8")
    except OSError as exc:
        fails.append(f"{label}: 读取失败：{exc}")
        return fails, warns, infos

    skill_dir = skill_md.parent

    name = skill_name_extract(text)
    desc = skill_desc_extract(text)
    if not name:
        fails.append(f"{label}: frontmatter 缺 `name`")
    elif name != skill_dir.name:
        fails.append(f"{label}: `name: {name}` 与目录名 `{skill_dir.name}` 不一致")
    if not desc:
        fails.append(f"{label}: frontmatter 缺 `description`")
    elif len(desc) > DESC_MAX:
        fails.append(f"{label}: description {len(desc)} 字 > {DESC_MAX}")
    elif len(desc) > DESC_WARN:
        warns.append(f"{label}: description {len(desc)} 字 > 预警线 {DESC_WARN}")

    body_lines = len(text.splitlines())
    if body_lines > BODY_MAX:
        fails.append(f"{label}: 正文 {body_lines} 行 > {BODY_MAX}")
    elif body_lines > BODY_WARN:
        warns.append(f"{label}: 正文 {body_lines} 行 > 预警线 {BODY_WARN}")

    direct: list[Path] = []
    for ref in md_links(text):
        target = resolve(skill_dir, ref)
        if not in_dir(target, skill_dir):
            infos.append(f"{label}: 链接指向 skill 目录外，不校验：{ref}")
            continue
        if target == skill_md.resolve():
            continue
        if not target.is_file():
            fails.append(f"{label}: 引用不存在：{ref}")
            continue
        direct.append(target)

    direct_set = set(direct)
    for target in direct:
        try:
            nested_text = target.read_text(encoding="utf-8")
        except OSError as exc:
            infos.append(f"{label}: 引用文件读取失败，跳过可达性检查：{target.name}（{exc}）")
            continue
        for nested_ref in md_links(nested_text):
            nested = resolve(target.parent, nested_ref)
            if not in_dir(nested, skill_dir):
                continue
            if nested == skill_md.resolve() or nested in direct_set:
                continue
            if not nested.is_file():
                continue
            fails.append(
                f"{label}: 引用深度 > 1（只能经第二跳到达）：{target.name} → {nested_ref}"
            )

    return fails, warns, infos


def find_skills(root: Path) -> list[Path]:
    if not root.is_dir():
        return []
    return sorted(p for p in root.glob("*/SKILL.md") if p.is_file())


def main() -> int:
    parser = argparse.ArgumentParser(description="skill 目录结构自检（只读）")
    parser.add_argument(
        "--skills-dir",
        default=str(SKILLS_DIR_DEFAULT),
        help=f"skills 根目录（默认 {SKILLS_DIR_DEFAULT}）",
    )
    args = parser.parse_args()

    root = Path(args.skills_dir).expanduser()
    skills = find_skills(root)
    if not skills:
        print(f"[FAIL] 未找到任何 `*/SKILL.md`（root={root}）", file=sys.stderr)
        return 2

    all_fails: list[str] = []
    all_warns: list[str] = []
    all_infos: list[str] = []
    for skill_md in skills:
        fails, warns, infos = check_skill(skill_md)
        all_fails += fails
        all_warns += warns
        all_infos += infos

    for line in all_fails:
        print(f"[FAIL] {line}")
    for line in all_warns:
        print(f"[WARN] {line}")
    for line in all_infos:
        print(f"[INFO] {line}")

    print(
        f"\n扫描 {len(skills)} 个 skill：FAIL {len(all_fails)} / WARN {len(all_warns)} / INFO {len(all_infos)}"
    )
    return 1 if all_fails else 0


if __name__ == "__main__":
    sys.exit(main())
