#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# 把 Android 发布密钥配进 GitHub 仓库的 Secrets, 之后 GitHub Actions 打 APK 就自动用它签名 (.github/workflows/build.yml 的 android 任务)。
#   tools/release/set_android_secrets.sh <owner/repo> [密钥目录]
#   例: tools/release/set_android_secrets.sh zmnqaz/SwordmanHD ../SwordmanHD-keys
# 密钥目录里要有 release.keystore 和 android.env (里面是别名与密码, 见 docs/打包/Android.md「签名」)。需要 gh 命令行已登录 (gh auth login)。
# 配的是三项 Secrets: ANDROID_KEYSTORE_BASE64 / ANDROID_KEYSTORE_PASSWORD / ANDROID_KEY_ALIAS; 它们在 GitHub 上只能被工作流使用, 页面上读不回来。
# 密钥文件和密码**不要入库、不要发给别人、要自己备份**。本脚本只往 GitHub 写, 不把任何东西打印出来。
set -euo pipefail
REPO="${1:?用法: $0 <owner/repo> [密钥目录]}"
DIR="${2:-$(dirname "$0")/../../../SwordmanHD-keys}"
KS="$DIR/release.keystore"
ENVF="$DIR/android.env"
[ -f "$KS" ] || { echo "找不到 $KS" >&2; exit 1; }
[ -f "$ENVF" ] || { echo "找不到 $ENVF" >&2; exit 1; }
command -v gh >/dev/null || { echo "需要 gh 命令行 (https://cli.github.com/), 并 gh auth login" >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENVF"
: "${GODOT_ANDROID_KEYSTORE_RELEASE_USER:?android.env 里没有别名}"
: "${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:?android.env 里没有密码}"
base64 -w0 "$KS" | gh secret set ANDROID_KEYSTORE_BASE64 -R "$REPO"
printf '%s' "$GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD" | gh secret set ANDROID_KEYSTORE_PASSWORD -R "$REPO"
printf '%s' "$GODOT_ANDROID_KEYSTORE_RELEASE_USER" | gh secret set ANDROID_KEY_ALIAS -R "$REPO"
echo "已配置 $REPO 的 Android 签名 Secrets (ANDROID_KEYSTORE_BASE64 / _PASSWORD / ANDROID_KEY_ALIAS)。推 v* 标签发布时, 云端 APK 会用这把密钥签名。"
