#!/usr/bin/env bash
# Compila el núcleo CyberHex (Zig + C23) para Android usando el NDK instalado.
# Uso: ./build_android.sh [arm64-v8a] [armeabi-v7a] [x86_64] [x86]
# Sin argumentos compila SOLO arm64-v8a (ARMv8-A genérico + NEON, válido para
# cualquier móvil 64-bit, incluidos los Helio octa-core). Para afinar a un SoC
# concreto: CYBERHEX_CPU=cortex_a76 ./build_android.sh (u otro nombre válido de
# `zig build-lib -mcpu help`). Otros ABI: pasarlos como argumentos.
set -euo pipefail

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$CORE_DIR")"

ZIG="${ZIG:-}"
if [ -z "$ZIG" ]; then
  if command -v zig >/dev/null 2>&1; then
    ZIG="$(command -v zig)"
  elif [ -x "$HOME/dev/zig/zig" ]; then
    ZIG="$HOME/dev/zig/zig"
  else
    echo "error: zig no está en PATH" >&2
    exit 1
  fi
fi

NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
if [ -z "$NDK" ]; then
  SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  if [ -z "$SDK" ] && [ -f "$PROJECT_DIR/android/local.properties" ]; then
    SDK="$(grep -E '^sdk\.dir=' "$PROJECT_DIR/android/local.properties" | cut -d= -f2- || true)"
  fi
  [ -n "$SDK" ] || SDK="$HOME/android-sdk"
  NDK="$(ls -d "$SDK"/ndk/* 2>/dev/null | sort -V | tail -1 || true)"
fi
[ -n "$NDK" ] && [ -d "$NDK" ] || { echo "error: NDK de Android no encontrado" >&2; exit 1; }

PREBUILT="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
SYS="$PREBUILT/sysroot"
API="${CYBERHEX_ANDROID_API:-29}"
OUT_DIR="$PROJECT_DIR/android/app/src/main/jniLibs"

TARGETS=("$@")
if [ ${#TARGETS[@]} -eq 0 ]; then
  TARGETS=(arm64-v8a)
fi

for abi in "${TARGETS[@]}"; do
  case "$abi" in
    arm64-v8a)   ZT=aarch64-linux-android;  NDKARCH=aarch64-linux-android; CPUFLAG=(-mcpu "${CYBERHEX_CPU:-baseline}") ;;
    armeabi-v7a) ZT=arm-linux-androideabi;  NDKARCH=arm-linux-androideabi; CPUFLAG=(-mcpu baseline) ;;
    x86_64)      ZT=x86_64-linux-android;   NDKARCH=x86_64-linux-android; CPUFLAG=(-mcpu baseline) ;;
    x86)         ZT=x86-linux-android;      NDKARCH=i686-linux-android; CPUFLAG=(-mcpu baseline) ;;
    *) echo "error: ABI desconocida '$abi'" >&2; exit 1 ;;
  esac

  LIBDIR="$SYS/usr/lib/$NDKARCH/$API"
  [ -d "$LIBDIR" ] || { echo "error: no existe $LIBDIR" >&2; exit 1; }

  FFDIR="$CORE_DIR/third_party/ffmpeg-android/$abi"
  [ -f "$FFDIR/lib/libavformat.a" ] || {
    echo "error: faltan las librerías FFmpeg para $abi en $FFDIR" >&2
    echo "       ejecuta ./build_ffmpeg_android.sh $abi" >&2
    exit 1
  }

  LIBC="$(mktemp)"
  trap 'rm -f "$LIBC"' EXIT
  cat > "$LIBC" <<EOF
include_dir=$SYS/usr/include
sys_include_dir=$SYS/usr/include/$NDKARCH
cc_dir=$LIBDIR
crt_dir=$LIBDIR
msvc_lib_dir=
kernel32_lib_dir=
darwin_sdk_dir=
EOF

  mkdir -p "$OUT_DIR/$abi"
  echo "==> núcleo CyberHex para $abi ($ZT, API $API)"
  (
    cd "$CORE_DIR"
    "$ZIG" build-lib \
      -cflags -std=c23 -O3 -ffast-math -fno-math-errno -- ./src/audio.c ./src/decode_ffmpeg.c ./src/playlist.c ./src/lyrics.c ./src/library.c ./src/markers.c ./src/cue.c ./src/fileio.c ./src/analysis.c \
      -Ofast -target "$ZT" --libc "$LIBC" "${CPUFLAG[@]}" \
      -L "$LIBDIR" -L "$FFDIR/lib" -I vendor -I src -I "$FFDIR/include" \
      -lavformat -lavcodec -lavutil -lswresample -lm -ldl \
      -Mroot=src/root.zig -lc \
      --name cyberhex_core -dynamic \
      -femit-bin="$OUT_DIR/$abi/libcyberhex_core.so"
  )
  if [ -x "$PREBUILT/bin/llvm-strip" ]; then
    "$PREBUILT/bin/llvm-strip" --strip-unneeded "$OUT_DIR/$abi/libcyberhex_core.so"
  fi
  rm -f "$LIBC"
  trap - EXIT
done

echo "Core Android listo en $OUT_DIR"
