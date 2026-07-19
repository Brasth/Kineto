#!/bin/bash
set -euo pipefail

readonly REVISION="5359861c739e955e79d9a303bcbc70fb988958b1"
readonly MODEL="ggml-large-v3-turbo-q5_0.bin"
readonly EXPECTED_SIZE="574041195"
readonly EXPECTED_SHA256="394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2"
readonly ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly DIRECTORY="$ROOT/Models"
readonly FINAL="$DIRECTORY/$MODEL"
readonly PART="$FINAL.part"
readonly URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/$REVISION/$MODEL"

mkdir -p "$DIRECTORY"
curl --fail --location --continue-at - --output "$PART" "$URL"

readonly ACTUAL_SIZE="$(stat -f '%z' "$PART")"
readonly ACTUAL_SHA256="$(shasum -a 256 "$PART" | cut -d ' ' -f 1)"
if [[ "$ACTUAL_SIZE" != "$EXPECTED_SIZE" ]]; then
  echo "Model size mismatch: expected $EXPECTED_SIZE, received $ACTUAL_SIZE" >&2
  exit 1
fi
if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
  echo "Model SHA-256 mismatch" >&2
  exit 1
fi

mv -f "$PART" "$FINAL"
printf '%s  %s\n' "$EXPECTED_SHA256" "$MODEL" > "$DIRECTORY/$MODEL.sha256"
echo "Verified $FINAL"
