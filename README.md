# my-AI-Agent

一个用约200行代码实现的轻量级AI编程助手，展示了AI编程工具背后的核心原理。

## 简介

my-AI-Agent 是一个简单的编程代理实现，通过 OpenAI 兼容 API 与大语言模型交互，支持文件读写、目录浏览等基本编程操作。

核心思想：AI 模型不直接访问文件系统，而是请求操作，由本地代码执行，结果再返回给模型进行下一步决策。

## 功能特性

- **读取文件**: 让 AI 能够查看项目中的文件内容
- **列出文件**: 使 AI 能够在项目目录间导航
- **编辑文件**: 允许 AI 创建和修改文件内容
- **可配置模型**: 通过环境变量自定义 API 端点和模型

## 快速开始

### 环境要求

- Python 3.7+
- OpenAI 兼容 API 密钥

### 安装

```bash
pip install -r requirements.txt
cp .env.example .env
# 编辑 .env 文件，填入你的 API Key
```

### 配置

在 `.env` 文件中设置以下环境变量：

| 变量 | 说明 | 默认值 |
|:---|:---|:---|
| `AI_API_KEY` | API 密钥 | 无（必填） |
| `AI_API_BASE` | API 端点 | `https://ark.cn-beijing.volces.com/api/v3` |
| `AI_MODEL_NAME` | 模型名称 | `gpt-3.5-turbo` |

### 运行

```bash
python main.py
```

### Docker 部署

```bash
docker compose up -d
```

## 使用示例

启动后可与 AI 助手进行对话：

```
You: 创建一个 hello.py 文件，写入 Hello World 程序
Assistant: 完成了！已创建 hello.py

You: 编辑 hello.py 并添加一个乘法函数
Assistant: 已添加 multiply(a, b) 函数
```

## 架构设计

```
用户输入 → 代理循环 → LLM 响应 → 工具调用 → 文件系统操作
                ↑                                    |
                └──────────── 结果返回 ──────────────┘
```

### 核心组件

1. **工具层** — 文件读取、目录列举、文件编辑三个核心工具
2. **工具注册表** — 按名称查找和管理可用工具
3. **系统提示** — 从工具签名和文档字符串动态生成
4. **调用解析器** — 解析 LLM 响应中的 `tool: name({...})` 格式
5. **代理循环** — 外层处理用户输入，内层处理工具调用链

## 扩展方向

- 添加更多文件操作工具（grep、bash 等）
- 错误处理和恢复机制
- 上下文感知的文件摘要
- 流式响应支持

## 许可证

MIT License
