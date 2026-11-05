.DEFAULT_GOAL := dmg
SIGN_IDENTITY ?= Flick Self-Signed Code Signing
export SIGN_IDENTITY
.PHONY: app dmg install clean help

app:
	@bash Scripts/build-app.sh

dmg: app
	@bash Scripts/build-dmg.sh

install:
	@bash Scripts/build-app.sh --install

clean:
	rm -rf build

help:
	@echo 'make dmg     构建通用 App 并生成 DMG（默认）'
	@echo 'make app     仅构建 build/MouseMeter.app'
	@echo 'make install 构建并安装至 /Applications'
	@echo 'make clean   清理 build/ 打包产物'
