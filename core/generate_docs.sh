#!/bin/bash
# Genera documentación HTML con Doxygen

set -e

cd "$(dirname "$0")"

if ! command -v doxygen &> /dev/null; then
    echo "Doxygen no instalado. En Ubuntu: sudo apt-get install doxygen graphviz"
    exit 1
fi

echo "Generando documentación..."
doxygen Doxyfile

echo "Documentación generada en docs/html/index.html"