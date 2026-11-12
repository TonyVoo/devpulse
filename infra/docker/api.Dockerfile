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
# PORT (Render sets it; default 8000) and WEB_CONCURRENCY (uvicorn worker processes; 1 fits
# small instances, ~CPU count on larger ones). FORWARDED_ALLOW_IPS limits who may set
# X-Forwarded-* (the platform's proxy); "*" is only correct behind a trusted proxy.
ENV PORT=8000 WEB_CONCURRENCY=1 FORWARDED_ALLOW_IPS=127.0.0.1
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port \"$PORT\" --workers \"$WEB_CONCURRENCY\" --proxy-headers --forwarded-allow-ips \"$FORWARDED_ALLOW_IPS\""]
