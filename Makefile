.DEFAULT_GOAL := dmg
SIGN_IDENTITY ?= Flick Self-Signed Code Signing
export SIGN_IDENTITY
.PHONY: app dmg install run clean help

app:
	@bash Scripts/build-app.sh

dmg: app
	@bash Scripts/build-dmg.sh

install:
	@bash Scripts/build-app.sh --install

# 仅构建本机架构以加快速度；先退出正在运行的 MouseMeter（同一 Bundle ID 下 open 只会激活旧进程）
run:
	@ARCH=$$(uname -m) bash Scripts/build-app.sh
	@pkill -x MouseMeter && while pgrep -x MouseMeter >/dev/null; do sleep 0.2; done || true
	@open build/MouseMeter.app

clean:
	rm -rf build

help:
	@echo 'make dmg     构建通用 App 并生成 DMG（默认）'
	@echo 'make app     仅构建 build/MouseMeter.app'
	@echo 'make install 构建并安装至 /Applications'
	@echo 'make run     构建本机架构并直接打开 build/MouseMeter.app（不安装）'
	@echo 'make clean   清理 build/ 打包产物'
