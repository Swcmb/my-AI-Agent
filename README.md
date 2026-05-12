# 魔法背后：如何用200行代码构建AI编程助手

## 皇帝的新衣：200行代码实现Claude编码原理

**2025年1月**

今天我们使用的AI编程助手感觉像魔法一样。你用有时甚至不太连贯的中文描述你想要的东西，它们就能读取文件、编辑你的项目并编写功能代码。

但事实是：这些工具的核心并不是魔法。它只是大约200行简单的Python代码。

让我们从零开始构建一个功能性的编程代理。

## 思维模型

在我们编写任何代码之前，让我们理解使用编程代理时实际发生的事情。本质上就是一个与拥有工具箱的强大LLM的对话。

1. 你发送一条消息（"创建一个包含hello world函数的新文件"）
2. LLM决定需要一个工具，并响应结构化的工具调用（或多个工具调用）
3. 你的程序在本地执行该工具调用（实际创建文件）
4. 结果被发送回LLM
5. LLM使用该上下文继续或响应

这就是整个循环。LLM永远不会真正接触你的文件系统。它只是要求事情发生，而你的代码使它们发生。

## 你需要的三个工具

我们的编程代理从根本上需要三种能力：

1. **读取文件**，这样LLM可以查看你的代码
2. **列出文件**，以便在你的项目中导航
3. **编辑文件**，以便能够发出创建和修改代码的指令

就是这样。像Claude Code这样的生产代理还有一些额外的功能，如[grep](./grep)、[bash](./bash)、[websearch](./websearch)等，但对于我们的目的来说，我们将看到这三个工具足以完成令人难以置信的事情。

## 搭建框架

我们从基本导入和API客户端开始。我在这里使用OpenAI，但这适用于任何LLM提供商：

```python
import inspect
import json
import os

import anthropic
from dotenv import load_dotenv
from pathlib import Path
from typing import Any, Dict, List, Tuple

load_dotenv()

claude_client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])
```

一些终端颜色使输出更易读：

```python
YOU_COLOR = "\u001b[94m"
ASSISTANT_COLOR = "\u001b[93m"
RESET_COLOR = "\u001b[0m"
```

以及一个解析文件路径的实用程序（所以[file.py](./file.py)变成`/Users/you/project/[file.py](./file.py)`）：

```python
def resolve_abs_path(path_str: str) -> Path:
    """
    [file.py](./file.py) -> /Users/you/project/[file.py](./file.py)
    """
    path = Path(path_str).expanduser()
    if not path.is_absolute():
        path = (Path.cwd() / path).resolve()
    return path
```

## 实现工具

请注意，你应该详细说明工具函数的文档字符串，因为LLM将在对话期间使用它们来推理应该调用哪些工具。详情见下文。

### 工具1：读取文件

最简单的工具。获取文件名，返回其内容：

```python
def read_file_tool(filename: str) -> Dict[str, Any]:
    """
    获取用户提供文件的全部内容。
    :param filename: 要读取的文件名。
    :return: 文件的完整内容。
    """
    full_path = resolve_abs_path(filename)
    print(full_path)
    with open(str(full_path), "r") as f:
        content = f.read()
    return {
        "file_path": str(full_path),
        "content": content
    }
```

我们返回一个字典，因为LLM需要关于发生情况的结构化上下文。

### 工具2：列出文件

通过列出其内容来导航目录：

```python
def list_files_tool(path: str) -> Dict[str, Any]:
    """
    列出用户提供目录中的文件。
    :param path: 要列出文件的目录路径。
    :return: 目录中文件的列表。
    """
    full_path = resolve_abs_path(path)
    all_files = []
    for item in full_path.iterdir():
        all_files.append({
            "filename": item.name,
            "type": "file" if item.is_file() else "dir"
        })
    return {
        "path": str(full_path),
        "files": all_files
    }
```

### 工具3：编辑文件

这是最复杂的工具，但仍然很简单。它处理两种情况：

1. 当[old_str](./old_str)为空时创建新文件
2. 通过查找和替换来替换文本

```python
def edit_file_tool(path: str, old_str: str, new_str: str) -> Dict[str, Any]:
    """
    替换文件中第一次出现的old_str为new_str。如果old_str为空，
    则创建/覆盖文件为new_str。
    :param path: 要编辑的文件路径。
    :param old_str: 要替换的字符串。
    :param new_str: 要替换成的字符串。
    :return: 包含文件路径和执行操作的字典。
    """
    full_path = resolve_abs_path(path)
    if old_str == "":
        full_path.write_text(new_str, encoding="utf-8")
        return {
            "path": str(full_path),
            "action": "created_file"
        }
    original = full_path.read_text(encoding="utf-8")
    if original.find(old_str) == -1:
        return {
            "path": str(full_path),
            "action": "old_str not found"
        }
    edited = original.replace(old_str, new_str, 1)
    full_path.write_text(edited, encoding="utf-8")
    return {
        "path": str(full_path),
        "action": "edited"
    }
```

这里的约定是：空的[old_str](./old_str)表示"创建此文件"。否则，查找并替换。真正的IDE在找不到字符串时会添加复杂的备用行为，但这种方法有效。

## 工具注册表

我们需要一种按名称查找工具的方法：

```python
TOOL_REGISTRY = {
    "read_file": read_file_tool,
    "list_files": list_files_tool,
    "edit_file": edit_file_tool 
}
```

## 教LLM了解我们的工具

LLM需要知道存在什么工具以及如何调用它们。我们从函数签名和文档字符串动态生成这些信息：

```python
def get_tool_str_representation(tool_name: str) -> str:
    tool = TOOL_REGISTRY[tool_name]
    return f"""
    Name: {tool_name}
    Description: {tool.__doc__}
    Signature: {inspect.signature(tool)}
    """

def get_full_system_prompt():
    tool_str_repr = ""
    for tool_name in TOOL_REGISTRY:
        tool_str_repr += "TOOL\n===" + get_tool_str_representation(tool_name)
        tool_str_repr += f"\n{'='*15}\n"
    return SYSTEM_PROMPT.format(tool_list_repr=tool_str_repr)
```

系统提示本身：

```
SYSTEM_PROMPT = """
You are a coding assistant whose goal it is to help us solve coding tasks. 
You have access to a series of tools you can execute. Here are the tools you can execute:

{tool_list_repr}

When you want to use a tool, reply with exactly one line in the format: 'tool: TOOL_NAME(JSON_ARGS)' and nothing else.
Use compact single-line JSON with double quotes. After receiving a tool_result(...) message, continue the task.
If no tool is needed, respond normally.
"""
```

这是关键见解：我们只是告诉LLM"这里是你的工具，这里是调用它们的格式。"LLM会弄清楚何时以及如何使用它们。

## 解析工具调用

当LLM响应时，我们需要检测它是否要求我们运行工具：

```python
def extract_tool_invocations(text: str) -> List[Tuple[str, Dict[str, Any]]]:
    """
    返回'工具: 名称({...})'行中请求的(工具名, 参数)列表。
    解析器期望括号中的单行紧凑JSON。
    """
    invocations = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line.startswith("tool:"):
            continue
        try:
            after = line[len("tool:"):].strip()
            name, rest = after.split("(", 1)
            name = name.strip()
            if not rest.endswith(")"):
                continue
            json_str = rest[:-1].strip()
            args = json.loads(json_str)
            invocations.append((name, args))
        except Exception:
            continue
    return invocations
```

简单文本解析。查找以`tool:`开头的行，提取函数名和JSON参数。

## LLM调用

API的简单包装：

```python
def execute_llm_call(conversation: List[Dict[str, str]]):
    system_content = ""
    messages = []
    
    for msg in conversation:
        if msg["role"] == "system":
            system_content = msg["content"]
        else:
            messages.append(msg)
    
    response = claude_client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=2000,
        system=system_content,
        messages=messages
    )
    return response.content[0].text
```

## 代理循环

现在我们把所有内容放在一起。这就是"魔法"发生的地方：

```python
def run_coding_agent_loop():
    print(get_full_system_prompt())
    conversation = [{
        "role": "system",
        "content": get_full_system_prompt()
    }]
    while True:
        try:
            user_input = input(f"{YOU_COLOR}You:{RESET_COLOR}:")
        except (KeyboardInterrupt, EOFError):
            break
        conversation.append({
            "role": "user",
            "content": user_input.strip()
        })
        while True:
            assistant_response = execute_llm_call(conversation)
            tool_invocations = extract_tool_invocations(assistant_response)
            if not tool_invocations:
                print(f"{ASSISTANT_COLOR}Assistant:{RESET_COLOR}: {assistant_response}")
                conversation.append({
                    "role": "assistant",
                    "content": assistant_response
                })
                break
            for name, args in tool_invocations:
                tool = TOOL_REGISTRY[name]
                resp = ""
                print(name, args)
                if name == "read_file":
                    resp = tool(args.get("filename", "."))
                elif name == "list_files":
                    resp = tool(args.get("path", "."))
                elif name == "edit_file":
                    resp = tool(args.get("path", "."), 
                                args.get("old_str", ""), 
                                args.get("new_str", ""))
                conversation.append({
                    "role": "user",
                    "content": f"tool_result({json.dumps(resp)})"
                })
```

结构：

- 外层循环：获取用户输入，添加到对话
- 内层循环：调用LLM，检查工具调用
  - 如果不需要工具，打印响应并中断内层循环
  - 如果需要工具，执行它们，将结果添加到对话，再次循环

内部循环持续直到LLM响应时不请求任何工具。这使得代理能够链接多个工具调用（读取文件，然后编辑它，然后确认编辑）。

## 运行

```
if __name__ == "__main__":
    run_coding_agent_loop()
```

现在你可以进行如下对话：

你：给我创建一个名为[hello.py](./hello.py)的新文件，在其中实现hello world

代理调用edit_file，参数为path="[hello.py](./hello.py)"，[old_str](./old_str)=""，[new_str](./new_str)="print('Hello World')"

助手：完成了！创建了[hello.py](./hello.py)，包含hello world实现。

或者多步骤交互：

你：编辑[hello.py](./hello.py)并添加一个用于乘以两个数字的函数

代理调用read_file以查看当前内容。代理调用edit_file添加函数。

助手：向[hello.py](./hello.py)添加了一个multiply函数。

## 我们构建的内容与生产工具对比

这大约有200行代码。像Claude Code这样的生产工具增加了：

- 更好的错误处理和备用行为
- 流式响应以获得更好的用户体验
- 更智能的上下文管理（摘要长文件等）
- 更多工具（运行命令、搜索代码库等）
- 对破坏性操作的审批工作流

但是核心循环？这正是我们在此处构建的内容。LLM决定要做什么，你的代码执行它，结果回流。这就是整个架构。

## 自己试试

完整源代码大约200行。插入你喜欢的LLM提供商，调整系统提示，作为练习添加更多工具。你会惊讶于这种简单模式的能力。

这是我的现代AI软件工程课程第一模块的一部分，基于我在斯坦福大学的讲座。在这里查看：

[python](./tags/python)a[illm](./tags/illm)coding-agents[tutorial](./tags/tutorial)

喜欢你所阅读的内容吗？我很想听到你的反馈！🙂

# my-AI-Agent

一个用约200行代码实现的轻量级AI编程助手，灵感来源于对现有AI编程工具核心原理的研究。

## 简介

my-AI-Agent 是一个简单的编程代理实现，展示了AI编程助手背后的基本原理。该项目证明了看似复杂的AI编程助手实际上可以通过简单的工具和循环逻辑实现。

核心思想是：AI模型不直接访问文件系统，而是请求操作，由本地代码执行这些操作，结果再返回给AI模型进行下一步决策。

## 功能特性

- **读取文件**: 让AI能够查看项目中的文件内容
- **列出文件**: 使AI能够在项目目录间导航
- **编辑文件**: 允许AI创建和修改文件内容
- **工具化交互**: 通过结构化工具调用来执行任务

## 架构设计

系统由以下组件构成：

1. **工具层**: 实现对文件系统的访问（读取、写入、列目录）
2. **工具注册表**: 管理可用工具的中央注册表
3. **系统提示**: 动态生成工具描述并提供给AI模型
4. **工具调用解析器**: 解析AI模型的工具调用请求
5. **代理循环**: 核心交互循环，处理用户输入和AI响应

## 安装与使用

### 环境要求

- Python 3.7+
- Anthropic API客户端或其他LLM提供商
- python-dotenv

### 安装步骤

1. 克隆仓库
2. 安装依赖包
3. 设置环境变量

```
pip install anthropic python-dotenv
```

创建 `.env` 文件并添加API密钥：

```
ANTHROPIC_API_KEY=your_api_key_here
```

### 运行

```
python main.py
```

## 使用示例

启动程序后，您可以与AI助手进行对话：

```
You:> 创建一个hello.py文件，写入Hello World程序
Assistant:> tool: edit_file({"path": "hello.py", "old_str": "", "new_str": "print('Hello World')"})
...
```

多步骤交互示例：
```
You:> 编辑hello.py并添加一个用于乘以两个数字的函数
Assistant:> tool: read_file({"filename": "hello.py"})
Assistant:> tool: edit_file({"path": "hello.py", "old_str": "print('Hello World')", "new_str": "print('Hello World')\n\ndef multiply(a, b):\n    return a * b"})
...
```

## 设计理念

这个项目的目的是展示AI编程助手的核心概念：

- AI模型仅提供指导，实际文件操作由本地代码执行
- 安全的沙盒环境，防止AI直接修改意外文件
- 简洁的架构，易于理解和扩展
- 工具驱动的交互模式

## 扩展建议

有兴趣的开发者可以考虑添加以下功能：

- 更多文件操作工具
- 错误处理和恢复机制
- 上下文感知的文件摘要
- 命令执行工具
- 代码质量检查工具
- 流式响应以获得更好的用户体验

## 贡献

欢迎提交Issue和Pull Request来改进项目。

## 许可证

MIT License
