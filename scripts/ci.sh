#!/usr/bin/env bash
# FIVO 的花花 — 本地 CI 入口
#
# 用法：
#   ./scripts/ci.sh            # Debug 构建 + 单元/集成测试 + UI 测试
#   ./scripts/ci.sh build      # 仅构建
#   ./scripts/ci.sh unit       # 仅单元与集成测试
#   ./scripts/ci.sh ui         # 仅 UI 测试
#
# 可通过环境变量覆盖：
#   SIMULATOR_NAME=iPhone 15
#   SIMULATOR_OS=17.2

set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="FivoFlower.xcodeproj"
SCHEME="FivoFlower"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 15}"
SIMULATOR_OS="${SIMULATOR_OS:-17.2}"
DESTINATION="platform=iOS Simulator,name=${SIMULATOR_NAME},OS=${SIMULATOR_OS}"
MODE="${1:-all}"

log() {
  printf '\n==> %s\n' "$1"
}

build() {
  log "构建 ${SCHEME}"
  xcodebuild \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration Debug \
    -destination "${DESTINATION}" \
    CODE_SIGNING_ALLOWED=NO \
    build
}

unit_tests() {
  log "单元与集成测试"
  xcodebuild test \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -destination "${DESTINATION}" \
    -only-testing:FivoFlowerTests \
    CODE_SIGNING_ALLOWED=NO
}

ui_tests() {
  log "UI 测试"
  xcodebuild test \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -destination "${DESTINATION}" \
    -only-testing:FivoFlowerUITests \
    CODE_SIGNING_ALLOWED=NO
}

case "${MODE}" in
  build) build ;;
  unit) unit_tests ;;
  ui) ui_tests ;;
  all)
    build
    unit_tests
    ui_tests
    ;;
  *)
    echo "未知模式：${MODE}（可选 build / unit / ui / all）" >&2
    exit 1
    ;;
esac

log "完成"
