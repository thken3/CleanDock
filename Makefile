APP = build/CleanDock.app

.PHONY: app zip test clean

app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/CleanDock $(APP)/Contents/MacOS/CleanDock
	cp Support/Info.plist $(APP)/Contents/Info.plist
	cp Support/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	codesign --force --sign - $(APP)

zip: app
	cd build && rm -f CleanDock.zip && ditto -c -k --keepParent CleanDock.app CleanDock.zip

test:
	swift test

clean:
	rm -rf .build build
