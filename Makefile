.PHONY: icon test contract-test app-test ui-test mac-test generate mac ipad iphone ipad-device import-spike

# The Swift package, then the client against Kennel's module inkhash (ADR 0067).
test:
	swift test --package-path Packages/InkhashCore
	tools/contract-test.sh

# The Swift client against Kennel's test server on a free port. Needs a Kennel checkout in
# KENNEL_DIR, by default ../kennel; without one it is skipped with a warning.
contract-test:
	tools/contract-test.sh

generate:
	xcodegen generate

# Editor tests in the iPad simulator: a real UITextView, typed into through its delegate.
app-test: generate
	xcodebuild -scheme Inkhash -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=latest' -derivedDataPath .build/xcode CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES test

# UI tests in the iPhone simulator against Kennel's test server; skipped without a Kennel checkout.
ui-test: generate
	tools/ui-test.sh

# The Mac editor and note sheet, without the app and without the real library.
mac-test: generate
	xcodebuild -scheme InkhashMacTests -destination 'platform=macOS' -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO test

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


# Lays out the painted app icon from tools/AppIconArtwork.png and cuts the mark out of it. See ADR 0066.
icon:
	mkdir -p .build/icon
	swiftc -parse-as-library -O App/Shared/Theme.swift tools/RenderIcon.swift -o .build/icon/render-icon
	swiftc -O tools/CutMark.swift -o .build/icon/cut-mark
	.build/icon/render-icon App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
	.build/icon/render-icon --mac App/Resources/Assets.xcassets/AppIcon.appiconset
	.build/icon/cut-mark tools/AppIconArtwork.png App/Resources/Assets.xcassets/InkhashMark.imageset/InkhashMark.png
	.build/icon/cut-mark tools/AppIconArtwork.png Website/mark.png

# Spike for ADR 0024 and 0041: PDF export or .goodnotes notebook to PKDrawing blobs and PNG previews.
# make import-spike FILE=path/to/export.pdf or notebook.goodnotes  ->  .build/import-spike/<name>/
import-spike:
	@test -n "$(FILE)" || { echo "FILE=export.pdf oder notebook.goodnotes setzen."; exit 1; }
	mkdir -p .build/import-spike
	# PencilKit writes preferences and traps without a bundle identifier; the plist rides inside the binary.
	# InkhashCore imports KennelKit (ADR 0073): built first as a module of its own from KENNELKIT_DIR, by default ../kennel.
	swiftc -parse-as-library -O -module-name KennelKit -emit-module -emit-module-path .build/import-spike/KennelKit.swiftmodule \
		-static -emit-library -o .build/import-spike/libKennelKit.a $(or $(KENNELKIT_DIR),../kennel)/clients/swift/Sources/KennelKit/*.swift
	swiftc -parse-as-library -O -I .build/import-spike -L .build/import-spike -lKennelKit \
		tools/PdfInkSpike.swift App/Shared/InkImport.swift Packages/InkhashCore/Sources/InkhashCore/*.swift \
		-Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker tools/PdfInkSpike-Info.plist \
		-o .build/import-spike/pdf-ink-spike
	.build/import-spike/pdf-ink-spike "$(FILE)" ".build/import-spike/$(notdir $(basename $(FILE)))"
