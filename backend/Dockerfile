# Build context: repository root (the backend needs ../schemas).
FROM python:3.13-slim

WORKDIR /srv/backend
COPY backend/pyproject.toml ./
COPY backend/app ./app
RUN pip install --no-cache-dir .

COPY backend/alembic.ini ./
COPY backend/alembic ./alembic
COPY schemas /srv/schemas

ENV PYTHONUNBUFFERED=1 \
    SCHEMA_DIR=/srv/schemas
EXPOSE 8000
CMD ["sh", "-c", "alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port 8000"]
