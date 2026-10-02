# 个人仓库与上游同步

- 默认仓库：`git@github.com:Tsingv/rime-ice-me.git`（origin，main）。
- 雾凇上游：`https://github.com/iDvel/rime-ice.git`（upstream，main）。
- 定时同步：每天北京时间 06:23，也可在 Actions 手动运行
  `Sync upstream with personal settings`。GitHub 调度可能延迟。
- 同步上游现存文件的最新内容，再启用 `rime_ice.dict.yaml` 中的
  `cn_dicts/41448`，确保紧接 `cn_dicts/8105`；字表结构变化则停止。
- 保留上下文调频脚本、测试、全拼与小鹤的 custom 配置，以及同步工具本身。
  `.gitignore`、`.github/`、`AGENTS.md`、`README.md`、拆字方案和
  `lua/search.lua` 按仓库约定保留。不会删除文件，上游删除的文件也会保留。
- 其他上游文件采用上游版本，不做 Git 合并；以后新增个人定制时，须加入
  `others/script/sync_upstream.py` 的保护规则。
- 构建、lint 和调频回归测试通过才自动提交推送；推送遇到并发更新则失败，
  不强制推送。CI 更新仓库后，本机运行 `git pull --ff-only` 并重新部署输入法。
- 用户词频数据、同步目录和设备配置保持忽略，不上传使用记录。

GitHub 定时调度说明：
https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule

本地检查：

```sh
lua others/script/tests/context_rank_filter_test.lua
~/.venv/bin/python -B -m unittest discover -s others/script/tests -p 'test_*.py'
make -C others/script lint
```

构建词库使用 `make -C others/script build`。手动同步必须使用干净工作区：

```sh
git fetch upstream main
~/.venv/bin/python -B others/script/sync_upstream.py upstream/main
```
