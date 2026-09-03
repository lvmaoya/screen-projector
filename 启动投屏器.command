#!/bin/zsh
set -e

cd "${0:A:h}"
app_path="$PWD/dist/Mac投屏.app"

if [[ ! -d "$app_path" ]]; then
  echo "尚未找到免安装应用：$app_path"
  echo "请使用完整发布包。"
  read -k 1 "?按任意键退出…"
  exit 1
fi

open "$app_path"
