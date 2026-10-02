"""同步上游文件，保留本仓库的定制；只在干净工作区运行。"""

import re
import subprocess
import sys
from pathlib import Path


PROTECTED = {
    ".gitignore", "README.md", "AGENTS.md",
    "lua/search.lua", "lua/context_rank_filter.lua",
    "others/script/sync_upstream.py",
    "others/script/tests/test_sync_upstream.py",
    "others/script/tests/context_rank_filter_test.lua",
    "others/docs/Fork-sync.md",
}


def protected(path):
    return (path in PROTECTED or path.startswith(".github/")
            or path.endswith(".custom.yaml")
            or (path.startswith("radical_pinyin.") and path.endswith(".yaml")))


def enable_large_table(text):
    pattern = r"(?m)^(\s*)#\s*(- cn_dicts/41448\b[^\n]*)$"
    text = re.sub(pattern, r"\1\2", text)
    tables = re.findall(r"(?m)^\s*- (cn_dicts/\w+)\b", text)
    if tables.count("cn_dicts/41448") != 1 or "cn_dicts/8105" not in tables:
        raise ValueError("上游字表结构已变化，需要人工检查；取消同步")
    if tables.index("cn_dicts/41448") != tables.index("cn_dicts/8105") + 1:
        raise ValueError("大字表必须紧接 8105；取消同步")
    return text


def git(*args):
    return subprocess.check_output(["git", *args])


def main():
    root = Path(__file__).resolve().parents[2]
    import os
    os.chdir(root)
    if git("status", "--porcelain").strip():
        raise SystemExit("工作区不干净，取消同步")
    ref = sys.argv[1] if len(sys.argv) > 1 else "upstream/main"
    revision = git("rev-parse", "--verify", ref + "^{commit}").decode().strip()
    # 在覆盖任何文件之前验证新字表结构。
    dictionary = enable_large_table(
        git("show", revision + ":rime_ice.dict.yaml").decode("utf-8"))
    paths = [p.decode("utf-8") for p in git("ls-tree", "-rz", "--name-only", revision).split(b"\0") if p]
    paths = [p for p in paths if not protected(p)]
    # 仅复制上游仍存在的文件，不删除本地文件，也不导入上游提交历史。
    subprocess.run(["git", "restore", "--source=" + revision, "--worktree",
                    "--pathspec-from-file=-", "--pathspec-file-nul"],
                   input=b"\0".join(p.encode("utf-8") for p in paths) + b"\0", check=True)
    (root / "rime_ice.dict.yaml").write_text(dictionary, encoding="utf-8")
    print("已同步上游 " + revision + "，保留大字表与个人配置")


if __name__ == "__main__":
    main()
