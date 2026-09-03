#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
build_dir="$project_dir/.portable-build"
download_dir="$build_dir/downloads"
stage_dir="$build_dir/stage"
app_dir="$project_dir/dist/Mac投屏.app"
scrcpy_version="4.1"

case "$(uname -m)" in
  arm64)
    scrcpy_arch="aarch64"
    scrcpy_sha="20fd47c9014dd5e0fa77091f3cb7adbda8445a360c4584aeaa0150b5b3988ff3"
    ;;
  x86_64)
    scrcpy_arch="x86_64"
    scrcpy_sha="ee2a7223bc8dbdc4f482db1134bcf441178dafb833492b71ca4c22090c58ce72"
    ;;
  *) echo "不支持的 Mac 架构：$(uname -m)" >&2; exit 1 ;;
esac

mkdir -p "$download_dir" "$stage_dir" "$project_dir/dist"
scrcpy_archive="$download_dir/scrcpy.tar.gz"
platform_archive="$download_dir/platform-tools.zip"

echo "下载官方便携组件…"
curl -L --fail --progress-bar \
  "https://github.com/Genymobile/scrcpy/releases/download/v${scrcpy_version}/scrcpy-macos-${scrcpy_arch}-v${scrcpy_version}.tar.gz" \
  -o "$scrcpy_archive"
actual_sha="$(shasum -a 256 "$scrcpy_archive" | awk '{print $1}')"
[[ "$actual_sha" == "$scrcpy_sha" ]] || { echo "scrcpy 校验失败，已停止构建。" >&2; exit 1; }

curl -L --fail --progress-bar \
  "https://dl.google.com/android/repository/platform-tools-latest-darwin.zip" \
  -o "$platform_archive"

rm -rf "$stage_dir/scrcpy" "$stage_dir/platform-tools"
mkdir -p "$stage_dir/scrcpy"
tar -xzf "$scrcpy_archive" -C "$stage_dir/scrcpy" --strip-components=1
unzip -q "$platform_archive" -d "$stage_dir"

echo "编译 macOS 应用…"
export CLANG_MODULE_CACHE_PATH="$build_dir/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_dir/module-cache"
swift build -c release --scratch-path "$build_dir/swift"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources/Tools"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
cp "$build_dir/swift/release/MacProjector" "$app_dir/Contents/MacOS/MacProjector"
cp -R "$stage_dir/scrcpy/"* "$app_dir/Contents/Resources/Tools/"
cp "$stage_dir/platform-tools/adb" "$app_dir/Contents/Resources/Tools/adb"
cp "$stage_dir/platform-tools/NOTICE.txt" "$app_dir/Contents/Resources/Tools/ANDROID_PLATFORM_TOOLS_NOTICE.txt"
chmod +x "$app_dir/Contents/MacOS/MacProjector" "$app_dir/Contents/Resources/Tools/adb" "$app_dir/Contents/Resources/Tools/scrcpy"
codesign --force --deep --sign - "$app_dir"

echo "完成：$app_dir"
