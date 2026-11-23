FROM python:3.15-slim-bookworm@sha256:96599df822d0e1c6bb700014a05c7f3c8cabc6e0f7ff3c4f9f69cee033b4b5d9
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
COPY requirements.lock ./
RUN --network=none --mount=type=bind,source=wheelhouse,target=/wheelhouse,ro \
    python -m pip install --no-cache-dir --disable-pip-version-check \
    --no-index --find-links=/wheelhouse --only-binary=:all: \
    --require-hashes -r requirements.lock
COPY decoder.py server.py ./
COPY Dockerfile ./build.Dockerfile
EXPOSE 8080
CMD ["python", "-I", "/app/server.py"]
