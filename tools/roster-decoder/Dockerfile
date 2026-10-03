FROM python:3.12-slim-bookworm@sha256:392307d22300de8b5986851a12d9176dfc0fc073e65bf6523ebd7dcbeb23564e
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
