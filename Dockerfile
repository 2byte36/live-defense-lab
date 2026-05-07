FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV GROUP_NAME="Workshop Group"
ENV DATABASE_PATH="/app/data/helpdesk.db"
ENV LOG_DIR="/logs"

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .
RUN mkdir -p /app/data /logs/web /logs/suricata

EXPOSE 5000

CMD ["python", "app.py"]
