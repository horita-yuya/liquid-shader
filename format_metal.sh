#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="metal-formatter:google"

if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
  echo "[build] Building Docker image: $IMAGE_NAME"
  docker build -t "$IMAGE_NAME" -f Dockerfile .
fi

docker run --rm \
  -u "$(id -u):$(id -g)" \
  -v "$PWD":/work -w /work \
  "$IMAGE_NAME" \
  bash -lc '
    find . \
      -path "*/.git" -prune -o \
      -path "*/.build" -prune -o \
      -path "*/.swiftpm" -prune -o \
      -name "*.xcworkspace" -prune -o \
      -name "*.xcodeproj" -prune -o \
      -type f \( \
        -name "*.metal" -o \
        -name "*.h" -o -name "*.hpp" -o \
        -name "*.c" -o -name "*.cc" -o -name "*.cpp" -o \
        -name "*.m" -o -name "*.mm" \
      \) -print0 \
      | xargs -0 -r clang-format -i --style=Google
  '

echo "[done] Formatted!"

