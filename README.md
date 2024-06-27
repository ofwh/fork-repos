# Unlock Music Project - CLI Edition

Original: Web Edition https://git.unlock-music.dev/um/web

- [![Build Status](https://ci.unlock-music.dev/api/badges/um/cli/status.svg)](https://ci.unlock-music.dev/um/cli)
- [Release Download](https://git.unlock-music.dev/um/cli/releases/latest)
- [Latest Build](https://git.unlock-music.dev/um/-/packages/generic/cli-build/)

## Features

- [x] All Algorithm Supported By `unlock-music/web`
- [x] Complete Metadata & Cover Image

## Hou to Build

- Requirements: **Golang 1.19**

~~1. run `go install unlock-music.dev/cli/cmd/um@master`~~

1. run `go install cmd/um/main.go`
2. run `go build -v -trimpath -ldflags="-w -s -X main.AppVersion=<version>" -o um-linux-amd64 ./cmd/um`

eg.

```shell
# Linux
GOARCH=amd64 go build -v -trimpath -ldflags="-w -s -X main.AppVersion=1.0.0(20240627)" -o um-linux-amd64 ./cmd/um
GOARCH=arm64 go build -v -trimpath -ldflags="-w -s -X main.AppVersion=1.0.0(20240627)" -o um-linux-arm64 ./cmd/um
# Windows
GOOS=windows GOARCH=amd64 go build -v -trimpath -ldflags="-w -s -X main.AppVersion=1.0.0(20240627)" -o um-windows-amd64 ./cmd/um
# macOS
GOOS=darwin GOARCH=arm64 go build -v -trimpath -ldflags="-w -s -X main.AppVersion=1.0.0(20240627)" -o um-darwin-arm64 ./cmd/um
GOOS=darwin GOARCH=amd64 go build -v -trimpath -ldflags="-w -s -X main.AppVersion=1.0.0(20240627)" -o um-darwin-amd64 ./cmd/um
```

## How to use

- Drag the encrypted file to `um.exe` (Tested on Windows)
- Run: `./um [-o <output dir>] [-i] <input dir/file>`
- Use `./um -h` to show help menu
