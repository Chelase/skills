# Agent 预读检查清单

每次开始新 Phase 或新任务前，快速确认以下检查点。

## 1. 项目状态

- [ ] 当前是 Phase 几？还在 roadmap 范围内吗？（`project-docs/ROADMAP.md`）
- [ ] 如果有 GEO 相关工作，先读 `project-docs/GEO.md`

## 2. 工作底线（`.agent-rules/README.md` §5）

- [ ] 改 README 后同步中英文
- [ ] 改 Python CLI 后同步 PowerShell（通过 shell out，不重写逻辑）
- [ ] 改 `data/*.csv` 时不删列、新列必须可选
- [ ] 改 `prompts_enhancer.py` / `image_craft.py` 前后跑测试基线
- [ ] `private_config.json` 不入库、不打印 key
- [ ] 每行改动直接追溯到用户请求

## 3. 任务工作流（`.agent-rules/skills-workflow.md`）

- [ ] 当前任务匹配哪个场景？用推荐的技能了吗？
  - 新功能/需求收口 → `grill-with-docs` / `grill-me`
  - 核心增强逻辑 → `tdd`
  - 卡住的 bug → `diagnose`
  - 提交前 → `review`
- [ ] 修改提示词增强管线 → 必须用 `tdd`
- [ ] 新增/删除 CLI 参数 → 同步 README/README_CN/SKILL 三处

## 4. 提交前确认

- [ ] 改动前测试通过
- [ ] 改动后测试通过
- [ ] Python 文件可编译（`py_compile`）
- [ ] ROADMAP 对应项已勾选
- [ ] `.claude/` 等本地配置未意外纳入提交
