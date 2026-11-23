FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /srv

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

# Runs as a normal user, not root. The number matches runAsUser in the chart.
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser
USER 10001

# CI builds a second image with --build-arg BROKEN=1. It starts, but /ready
# answers 503, so Kubernetes never sends it traffic.
ARG BROKEN=0
ENV APP_BROKEN=${BROKEN}

EXPOSE 8080
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
