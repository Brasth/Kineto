#!/bin/bash
set -euo pipefail

readonly REPOSITORY="https://github.com/ggml-org/whisper.cpp.git"
readonly COMMIT="f049fff95a089aa9969deb009cdd4892b3e74916"
readonly ROOT="$(cd "$(dirname "$0")/.." && pwd)"
readonly OUTPUT="$ROOT/Binaries/CWhisper.xcframework"
readonly WORK="$(mktemp -d "${TMPDIR:-/tmp}/kineto-whisper.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

git clone --quiet --filter=blob:none "$REPOSITORY" "$WORK/whisper.cpp"
git -C "$WORK/whisper.cpp" checkout --quiet "$COMMIT"

cmake -S "$WORK/whisper.cpp" -B "$WORK/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=26.1 \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_METAL=ON \
  -DWHISPER_BUILD_EXAMPLES=OFF \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_SERVER=OFF
cmake --build "$WORK/build" --config Release --parallel

readonly FIRST_ARCHIVE="$(find "$WORK/build" -type f -name '*.a' -print -quit)"
if [[ -z "$FIRST_ARCHIVE" ]]; then
  echo "No static archives were produced" >&2
  exit 1
fi

mkdir -p "$WORK/include" "$ROOT/Binaries"
cp "$WORK/whisper.cpp/include/whisper.h" "$WORK/include/"
cp "$WORK/whisper.cpp/ggml/include/"*.h "$WORK/include/"
cat > "$WORK/include/module.modulemap" <<'MODULEMAP'
module CWhisper {
  header "whisper.h"
  export *
}
MODULEMAP
find "$WORK/build" -type f -name '*.a' -exec libtool -static -o "$WORK/libCWhisper.a" {} +
rm -rf "$OUTPUT"
xcodebuild -create-xcframework \
  -library "$WORK/libCWhisper.a" \
  -headers "$WORK/include" \
  -output "$OUTPUT"

printf '%s\n' "$COMMIT" > "$OUTPUT/WHISPER_CPP_COMMIT"
echo "Built $OUTPUT from $COMMIT"
