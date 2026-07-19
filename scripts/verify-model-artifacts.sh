#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODEL="$ROOT/Models/ggml-large-v3-turbo-q5_0.bin"
FRAMEWORK="$ROOT/Binaries/CWhisper.xcframework"
NOTICES="$ROOT/THIRD_PARTY_NOTICES"
EXPECTED_MODEL_BYTES=574041195
EXPECTED_MODEL_SHA256="394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2"
EXPECTED_WHISPER_COMMIT="f049fff95a089aa9969deb009cdd4892b3e74916"
EXPECTED_ARCHIVE_SHA256="698cb79de47c89986863ba4a24a0720563ea1a9c9a425b9c7a1d2fc2d739cbbc"
EXPECTED_HEADER_SHA256="6c1c70a5d4b74556f4253e51a13874ad013513b0ae62e779c0e30ffde3dc30ba"
EXPECTED_INFO_SHA256="d721f8ff693eb93a2b26f41d4d54a42dd82ccb85de428b3f30d9b65817c9c4b5"

[[ -f "$MODEL" ]] || { echo "Missing model: $MODEL" >&2; exit 1; }
[[ -d "$FRAMEWORK" ]] || { echo "Missing framework: $FRAMEWORK" >&2; exit 1; }
[[ -f "$NOTICES" ]] || { echo "Missing third-party notices" >&2; exit 1; }
grep "$EXPECTED_MODEL_SHA256" "$NOTICES" >/dev/null || {
  echo "Model digest is missing from third-party notices" >&2
  exit 1
}
grep "$EXPECTED_WHISPER_COMMIT" "$NOTICES" >/dev/null || {
  echo "whisper.cpp commit is missing from third-party notices" >&2
  exit 1
}

actual_bytes="$(stat -f '%z' "$MODEL")"
[[ "$actual_bytes" == "$EXPECTED_MODEL_BYTES" ]] || {
  echo "Model size mismatch: $actual_bytes" >&2
  exit 1
}

actual_sha256="$(shasum -a 256 "$MODEL" | cut -d ' ' -f 1)"
[[ "$actual_sha256" == "$EXPECTED_MODEL_SHA256" ]] || {
  echo "Model SHA-256 mismatch: $actual_sha256" >&2
  exit 1
}

commit_file="$FRAMEWORK/WHISPER_CPP_COMMIT"
[[ -f "$commit_file" ]] || { echo "Missing framework provenance" >&2; exit 1; }
actual_commit="$(tr -d '[:space:]' < "$commit_file")"
[[ "$actual_commit" == "$EXPECTED_WHISPER_COMMIT" ]] || {
  echo "whisper.cpp commit mismatch: $actual_commit" >&2
  exit 1
}

header="$FRAMEWORK/macos-arm64/Headers/whisper.h"
[[ -f "$header" ]] || { echo "Missing public whisper header" >&2; exit 1; }

archive="$FRAMEWORK/macos-arm64/libCWhisper.a"
info="$FRAMEWORK/Info.plist"
[[ -f "$archive" && -f "$info" ]] || {
  echo "Incomplete CWhisper XCFramework" >&2
  exit 1
}

[[ "$(shasum -a 256 "$archive" | cut -d ' ' -f 1)" == "$EXPECTED_ARCHIVE_SHA256" ]] || {
  echo "CWhisper archive checksum mismatch" >&2
  exit 1
}
[[ "$(shasum -a 256 "$header" | cut -d ' ' -f 1)" == "$EXPECTED_HEADER_SHA256" ]] || {
  echo "CWhisper header checksum mismatch" >&2
  exit 1
}
[[ "$(shasum -a 256 "$info" | cut -d ' ' -f 1)" == "$EXPECTED_INFO_SHA256" ]] || {
  echo "CWhisper Info.plist checksum mismatch" >&2
  exit 1
}
[[ "$(lipo -archs "$archive")" == "arm64" ]] || {
  echo "CWhisper archive has an unexpected architecture" >&2
  exit 1
}
nm -gU "$archive" | grep ' _whisper_init_from_file_with_params$' >/dev/null || {
  echo "CWhisper archive is missing its required public symbols" >&2
  exit 1
}
[[ "$(plutil -extract AvailableLibraries.0.SupportedArchitectures.0 raw "$info")" == "arm64" ]] || {
  echo "CWhisper XCFramework metadata architecture mismatch" >&2
  exit 1
}

printf 'Verified model %s bytes SHA-256 %s\n' "$actual_bytes" "$actual_sha256"
printf 'Verified whisper.cpp commit %s\n' "$actual_commit"
printf 'Verified CWhisper archive, headers, metadata, architecture, and symbols\n'
printf 'Verified third-party provenance notices\n'
