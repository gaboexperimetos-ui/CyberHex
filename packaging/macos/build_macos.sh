#!/usr/bin/env bash
#
# Compila el núcleo de CyberHex con Zig y empaqueta el bundle de Flutter para
# macOS. Un solo comando deja un `cyberhex.app` que arranca y encuentra su
# `libcyberhex_core.dylib`.
#
#   ./packaging/macos/build_macos.sh                  # núcleo auto + Flutter release
#   ./packaging/macos/build_macos.sh --decoder miniaudio
#   ./packaging/macos/build_macos.sh --skip-flutter    # solo el núcleo
#
# Requisitos: macOS con Xcode (command line tools), Flutter 3.x y Zig 0.17.x en
# el PATH. `core/build.zig` produce la biblioteca **dinámica**
# `libcyberhex_core.dylib` igual que en Linux; aquí solo cambia dónde hay que
# dejarla y cómo se lo tiene que creer el cargador de macOS.
#
# Si el repo no tiene `macos/` (runner de Flutter), este script se detiene y
# dice qué ejecutar: ese andamiaje lo genera el SDK, no se escribe a mano.
set -euo pipefail

DECODER="${DECODER:-auto}"
SKIP_FLUTTER=0

usage() {
  cat <<'TXT'
Uso: build_macos.sh [--decoder auto|ffmpeg|miniaudio] [--skip-flutter]

  --decoder       qué decodificador enlaza el núcleo (por defecto auto:
                  FFmpeg si está instalado, si no miniaudio)
  --skip-flutter  no llama a `flutter build macos`; solo compila el núcleo
TXT
}

die() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --decoder)
      [[ $# -ge 2 ]] || die "--decoder necesita un valor"
      DECODER="$2"
      shift 2
      ;;
    --decoder=*)
      DECODER="${1#*=}"
      shift
      ;;
    --skip-flutter)
      SKIP_FLUTTER=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      printf 'opción desconocida: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$DECODER" in
  auto | ffmpeg | miniaudio) ;;
  *) die "--decoder debe ser auto, ffmpeg o miniaudio (recibí '$DECODER')" ;;
esac

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo"

[[ "$(uname -s)" == "Darwin" ]] || die "este script es para macOS (estás en $(uname -s))"

for tool in zig flutter; do
  command -v "$tool" >/dev/null 2>&1 ||
    die "falta '$tool' en el PATH (Zig 0.17.x y Flutter 3.x)"
done

if [[ ! -d macos ]]; then
  die "no existe macos/: generalo antes con 'flutter create --platforms=macos .' y vuelve a lanzar esto"
fi

echo "==> núcleo: zig build -Doptimize=ReleaseFast -Ddecoder=$DECODER"
(
  cd core
  zig build -Doptimize=ReleaseFast -Ddecoder="$DECODER"
)

dylib="core/zig-out/lib/libcyberhex_core.dylib"
[[ -f "$dylib" ]] || dylib="core/zig-out/bin/libcyberhex_core.dylib"
[[ -f "$dylib" ]] ||
  die "no encuentro libcyberhex_core.dylib tras el build (¿core/zig-out?)"

if [[ $SKIP_FLUTTER -eq 0 ]]; then
  echo "==> app: flutter build macos --release"
  flutter build macos --release
fi

app="$(find build/macos/Build/Products/Release -maxdepth 1 -name '*.app' -print -quit 2>/dev/null || true)"
[[ -n "$app" ]] ||
  die "no encuentro el .app en build/macos/Build/Products/Release (¿lanzaste flutter build macos?)"

frameworks="$app/Contents/Frameworks"
mkdir -p "$frameworks"
cp -f "$dylib" "$frameworks/libcyberhex_core.dylib"

# El cargador de macOS busca por `install_name`, no por nombre de archivo: se
# reescribe el id a @rpath y se añade el rpath del bundle si Flutter no lo puso.
target="$frameworks/libcyberhex_core.dylib"
install_name_tool -id "@rpath/libcyberhex_core.dylib" "$target"

binary="$app/Contents/MacOS/$(basename "$app" .app)"
[[ -f "$binary" ]] || die "no encuentro el ejecutable dentro de $app"
if ! otool -l "$binary" | grep -q '@executable_path/../Frameworks'; then
  install_name_tool -add_rpath '@executable_path/../Frameworks' "$binary"
fi

# Tocar la biblioteca y el binario invalida la firma: se vuelve a firmar en
# ad-hoc para que Gatekeeper no lo rechace al abrirlo desde Finder.
codesign --force --deep --sign - "$app" >/dev/null 2>&1 ||
  echo "aviso: no pude firmar en ad-hoc; el .app se abre igual desde Terminal"

echo
echo "listo: $app"
du -sh "$app" 2>/dev/null || true
echo "núcleo: $target"
