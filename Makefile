.PHONY: icon test contract-test app-test server server-lan server-test server-package generate mac ipad iphone ipad-device import-spike

PORT ?= 8787

test:
	swift test --package-path Packages/InkhashCore
	@test -d Server/node_modules || npm --prefix Server ci
	npm --prefix Server test
	tools/contract-test.sh

# The Swift client against the real server on a free port. Part of `make test`. See ADR 0052.
contract-test:
	@test -d Server/node_modules || npm --prefix Server ci
	npm --prefix Server run build
	tools/contract-test.sh

server:
	@test -d Server/node_modules || npm --prefix Server ci
	npm --prefix Server run build
	INKHASH_DATA=$(CURDIR)/.data INKHASH_HOST=127.0.0.1 INKHASH_PORT=$(PORT) node Server/dist/inkhashd.js

# Until the first account exists, the server logs a setup token for /admin. See ADR 0021.
server-lan:
	@test -d Server/node_modules || npm --prefix Server ci
	npm --prefix Server run build
	INKHASH_DATA=$(CURDIR)/.data INKHASH_HOST=0.0.0.0 INKHASH_PORT=$(PORT) node Server/dist/inkhashd.js

# Test environment from .test-env/env: random port, all interfaces, own data directory.
server-test:
	@test -f .test-env/env || { echo ".test-env/env fehlt."; exit 1; }
	@test -d Server/node_modules || npm --prefix Server ci
	npm --prefix Server run build
	set -a && . ./.test-env/env && set +a && node Server/dist/inkhashd.js

# Release package as GitHub Releases has it: make server-package VERSION=0.1.0 -> .build/release/. See ADR 0039.
server-package:
	@test -n "$(VERSION)" || { echo "VERSION=X.Y.Z setzen."; exit 1; }
	deploy/package.sh $(VERSION)

generate:
	xcodegen generate

# Editor tests in the iPad simulator: a real UITextView, typed into through its delegate.
app-test: generate
	xcodebuild -scheme Inkhash -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=latest' -derivedDataPath .build/xcode CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES test

mac: generate
	xcodebuild -scheme InkhashMac -destination 'platform=macOS' -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO build

ipad: generate
	xcodebuild -scheme Inkhash -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=latest' -derivedDataPath .build/xcode CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES build

iphone: generate
	xcodebuild -scheme Inkhash -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -derivedDataPath .build/xcode CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES build

# Signed build on a physical iPad or iPhone. Needs an Apple account in Xcode > Settings > Accounts.
# make ipad-device TEAM=<team id> DEVICE=<udid from `xcrun devicectl list devices`>
ipad-device: generate
	@test -n "$(TEAM)" -a -n "$(DEVICE)" || { echo "TEAM und DEVICE setzen."; exit 1; }
	xcodebuild -scheme Inkhash -destination 'platform=iOS,id=$(DEVICE)' -derivedDataPath .build/device -allowProvisioningUpdates CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=$(TEAM) CODE_SIGN_IDENTITY="Apple Development" CODE_SIGNING_REQUIRED=YES build
	xcrun devicectl device install app --device $(DEVICE) .build/device/Build/Products/Debug-iphoneos/Inkhash.app
	xcrun devicectl device process launch --device $(DEVICE) local.inkhash.ipad


# Renders the app icon from InkhashMark in App/Shared/Theme.swift.
icon:
	mkdir -p .build/icon
	swiftc -parse-as-library -O App/Shared/Theme.swift tools/RenderIcon.swift -o .build/icon/render-icon
	.build/icon/render-icon App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
	.build/icon/render-icon --mac App/Resources/Assets.xcassets/AppIcon.appiconset

# Spike for ADR 0024 and 0041: PDF export or .goodnotes notebook to PKDrawing blobs and PNG previews.
# make import-spike FILE=path/to/export.pdf or notebook.goodnotes  ->  .build/import-spike/<name>/
import-spike:
	@test -n "$(FILE)" || { echo "FILE=export.pdf oder notebook.goodnotes setzen."; exit 1; }
	mkdir -p .build/import-spike
	# PencilKit writes preferences and traps without a bundle identifier; the plist rides inside the binary.
	swiftc -parse-as-library -O tools/PdfInkSpike.swift App/Shared/InkImport.swift Packages/InkhashCore/Sources/InkhashCore/*.swift \
		-Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker tools/PdfInkSpike-Info.plist \
		-o .build/import-spike/pdf-ink-spike
	.build/import-spike/pdf-ink-spike "$(FILE)" ".build/import-spike/$(notdir $(basename $(FILE)))"
