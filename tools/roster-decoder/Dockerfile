FROM python:3.15-slim-bookworm@sha256:4e03260adeeebafccd084f3584e6b84823aba5651cfb53ef8a078ed441ddf9cd
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
