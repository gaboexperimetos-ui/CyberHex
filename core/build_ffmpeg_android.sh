#!/usr/bin/env bash
# Compila FFmpeg (solo audio) para Android como librerías estáticas.
# Uso: ./build_ffmpeg_android.sh [arm64-v8a] [armeabi-v7a] [x86_64]
set -euo pipefail

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TP="$CORE_DIR/third_party"
SRC="$TP/ffmpeg-src"
OUT="$TP/ffmpeg-android"
VERSION="${FFMPEG_VERSION:-9.1}"
JOBS="${JOBS:-$(nproc)}"

NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
if [ -z "$NDK" ]; then
  SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/android-sdk}}"
  NDK="$(ls -d "$SDK"/ndk/* 2>/dev/null | sort -V | tail -1 || true)"
fi
[ -n "$NDK" ] && [ -d "$NDK" ] || { echo "error: NDK no encontrado" >&2; exit 1; }
PRE="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
API="${CYBERHEX_ANDROID_API:-29}"

mkdir -p "$TP"
if [ ! -d "$SRC" ]; then
  echo "==> descargando FFmpeg $VERSION"
  curl -L --fail -o "$TP/ffmpeg.tar.xz" "https://ffmpeg.org/releases/ffmpeg-$VERSION.tar.xz"
  tar -xf "$TP/ffmpeg.tar.xz" -C "$TP"
  mv "$TP/ffmpeg-$VERSION" "$SRC"
fi

TARGETS=("$@")
[ ${#TARGETS[@]} -gt 0 ] || TARGETS=(arm64-v8a armeabi-v7a x86_64)

for abi in "${TARGETS[@]}"; do
  case "$abi" in
    arm64-v8a)   ARCH=aarch64; CPU=armv8-a;  TRIPLE=aarch64-linux-android ;;
    armeabi-v7a) ARCH=arm;     CPU=armv7-a;  TRIPLE=armv7a-linux-androideabi ;;
    x86_64)      ARCH=x86_64;  CPU=x86-64;   TRIPLE=x86_64-linux-android ;;
    *) echo "error: ABI '$abi'" >&2; exit 1 ;;
  esac

  PREFIX="$OUT/$abi"
  BUILD="$TP/build-$abi"
  rm -rf "$BUILD"; mkdir -p "$BUILD" "$PREFIX"
  echo "==> FFmpeg $VERSION para $abi"

  (
    cd "$BUILD"
    "$SRC/configure" \
      --prefix="$PREFIX" \
      --target-os=android --arch="$ARCH" --cpu="$CPU" \
      --enable-cross-compile --disable-asm --enable-pic \
      --cc="$PRE/bin/$TRIPLE$API-clang" \
      --cxx="$PRE/bin/$TRIPLE$API-clang++" \
      --ar="$PRE/bin/llvm-ar" --ranlib="$PRE/bin/llvm-ranlib" \
      --strip="$PRE/bin/llvm-strip" --nm="$PRE/bin/llvm-nm" \
      --sysroot="$NDK/toolchains/llvm/prebuilt/linux-x86_64/sysroot" \
      --enable-static --disable-shared \
      --disable-programs --disable-doc \
      --disable-avdevice --disable-swscale --disable-postproc --disable-avfilter \
      --disable-network --disable-encoders --disable-muxers --disable-bsfs \
      --disable-indevs --disable-outdevs --disable-devices \
      --disable-autodetect --disable-iconv --disable-zlib --disable-bzlib \
      --disable-lzma --disable-xlib --disable-libxcb \
      --disable-symver >/dev/null
    make -j"$JOBS" >/dev/null
    make install >/dev/null
  )
  echo "==> listo $abi -> $PREFIX/lib"
done
