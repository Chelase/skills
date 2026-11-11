# 仓库背景

本仓库 `image-generation` 是开源 AI Agent 图像生成技能，产品名 **Image Craft**。

- **远端**：`https://github.com/Chelase/skills`（技能位于 `skills/image-craft/`）
- **许可证**：MIT
- **主语言**：Python（规范实现）+ PowerShell（镜像 CLI，shell out 调用 Python 处理提示词）
- **数据层**：`data/*.csv` —— 54 风格（`styles.csv`）/ 119 提示词模板（`prompts.csv`）/ 50 配色（`colors.csv`）
- **测试**：`tests/test_prompts_enhancer.py`，使用 `unittest`，运行命令 `python -m unittest discover tests`
- **默认 API 端点**：`https://right.codes/draw`（见 `private_config.json.example`）
- **默认模型**：`gpt-image-2-5-flare`（可选 `gpt-image-2-5-sunburst`）
- **配置优先级**：CLI 参数 > 环境变量 `IMAGE_CRAFT_*` > `private_config.json` > 默认值
- **当前阶段**：Phase 4 进行中（详见 `project-docs/ROADMAP.md`），Phase 5 GEO 已启动（详见 `project-docs/GEO.md`）

## 关键单一事实来源

| 内容 | 文件 |
|------|------|
| 功能开发进度 | `project-docs/ROADMAP.md` |
| GEO 工作执行 | `project-docs/GEO.md` |
| 技能能力描述（对外） | `SKILL.md` |
| 项目级 agent 规则 | `.agent-rules/` |
| CLI 参数定义 | `scripts/image_craft.py` 的 `build_parser` |
| 风格/模板/配色数据 | `data/*.csv` |

## 同类工作区交叉参考

`D:\code\work\wkbox-dev\wkbox-course-dotnet` 使用相同的 `.agent-rules/` + `CLAUDE.md` 桥接结构，本仓库的规则布局以其为参考。
