FROM python:3.11-slim

WORKDIR /app

# 安装依赖
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 复制源码
COPY main.py .
COPY .env.example .

# 环境变量占位（运行时通过 .env 或 -e 注入）
ENV AI_API_KEY=""
ENV AI_API_BASE="https://ark.cn-beijing.volces.com/api/v3"
ENV AI_MODEL_NAME="gpt-3.5-turbo"

CMD ["python", "main.py"]
