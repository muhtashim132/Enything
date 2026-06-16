#!/bin/bash
for arg in "$@"; do
    if [[ "$arg" == *.app || "$arg" == *.framework || "$arg" == *.dylib || "$arg" == *.bundle ]]; then
        /usr/bin/xattr -cr "$arg" 2>/dev/null || true
    fi
done
exec /usr/bin/codesign "$@"
