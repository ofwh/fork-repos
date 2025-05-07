#!/bin/bash -e
# see .gitea/workflows/build.yml

APP_VERSION="${1:-$(git describe --tags --always)}"

for exe in prepare/*/um-*.exe; do
    name="$(basename "$exe" .exe)-$APP_VERSION"
    new_exe="$(dirname "$exe")/um.exe"
    mv "$exe" "$new_exe"

    echo "archiving ${new_exe}..."
    zip -Xqj9 "dist/${name}.zip" "$new_exe"
    rm -f "$new_exe"
done

for exe in prepare/*/um-*; do
    name="$(basename "$exe")-$APP_VERSION"
    new_exe="$(dirname "$exe")/um"
    mv "$exe" "$new_exe"

    echo "archiving ${new_exe}..."
    tar \
        --sort=name --format=posix \
        --pax-option=exthdr.name=%d/PaxHeaders/%f \
        --pax-option=delete=atime,delete=ctime \
        --clamp-mtime --mtime='1970-01-01T00:00:00Z' \
        --numeric-owner --owner=0 --group=0 \
        --mode=0755 \
        -c -C "$(dirname "$exe")" um |
        gzip -9 >"dist/${name}.tar.gz"
    rm -f "$exe"
done

pushd dist

if command -v strip-nondeterminism >/dev/null 2>&1; then
    echo 'strip archives...'
    strip-nondeterminism *.zip *.tar.gz
fi

echo 'Creating checksum...'
sha256sum *.zip *.tar.gz >sha256sum.txt
popd
