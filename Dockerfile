# Two stages so the runtime image carries no compiler and no build cache.
#
# Pinned to a digest-free but minor-locked base tag deliberately: floating on
# `python:3` would change the interpreter under a filed calculation, and this
# application's whole claim is that a figure can be reproduced years later.

FROM python:3.12-slim-bookworm AS build

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /src

# Build-only toolchain. Present here, absent from the runtime stage.
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential libpq-dev \
 && rm -rf /var/lib/apt/lists/*

# Dependency metadata first, so a source-only change does not reinstall the
# whole dependency tree on every build.
COPY pyproject.toml README.md ./
COPY backend/app/__init__.py backend/app/__init__.py

RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install --upgrade pip \
 && /opt/venv/bin/pip install ".[postgres]"

COPY backend ./backend
COPY frontend ./frontend
COPY data ./data
COPY alembic.ini ./

RUN /opt/venv/bin/pip install --no-deps .


FROM python:3.12-slim-bookworm AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    FA_ENVIRONMENT=production \
    FA_STORAGE_ROOT=/var/lib/schedulefa/storage \
    FA_DATA_ROOT=/srv/app/data \
    FA_FRONTEND_ROOT=/srv/app/frontend

# libpq for psycopg, curl for the container healthcheck. Nothing else.
RUN apt-get update \
 && apt-get install -y --no-install-recommends libpq5 curl \
 && rm -rf /var/lib/apt/lists/*

# Unprivileged. The process only ever needs to write to the storage root,
# which is a volume owned by this user; the application tree stays read-only.
RUN useradd --system --create-home --uid 10001 appuser \
 && mkdir -p /var/lib/schedulefa/storage \
 && chown -R appuser:appuser /var/lib/schedulefa

COPY --from=build /opt/venv /opt/venv

WORKDIR /srv/app
COPY --chown=root:root backend ./backend
COPY --chown=root:root frontend ./frontend
COPY --chown=root:root data ./data
COPY --chown=root:root alembic.ini ./

USER appuser
EXPOSE 8000
VOLUME ["/var/lib/schedulefa/storage"]

# Hits the real health endpoint, which probes the database and the blob store
# rather than answering a constant. A container that cannot reach its
# database should not stay in the load balancer.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8000/api/v1/health || exit 1

CMD ["uvicorn", "backend.app.api.asgi:app", \
     "--host", "0.0.0.0", "--port", "8000", \
     "--proxy-headers", "--forwarded-allow-ips", "*"]
