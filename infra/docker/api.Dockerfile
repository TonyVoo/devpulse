# syntax=docker/dockerfile:1
FROM python:3.12-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /app

FROM base AS deps
COPY services/api/pyproject.toml ./
RUN mkdir app && touch app/__init__.py && pip install --prefix=/install .

FROM base AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends curl \
 && apt-get clean && rm -rf /var/lib/apt/lists/* \
 && useradd --create-home --uid 10001 devpulse
COPY --from=deps /install /usr/local
COPY services/api/ ./
USER devpulse
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]
