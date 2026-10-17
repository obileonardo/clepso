.PHONY: ci build test perf design-site clean-ci app

# Every quality gate, one pass/fail summary (docs/ROADMAP.md increment 0.5).
ci:
	@scripts/ci.sh

build:
	swift build --build-tests -Xswiftc -warnings-as-errors

test:
	swift test

# ADR-003 budget, enforced on this Mac: helper overhead ≤ 20 ms p95 over 200 release-build runs.
perf:
	PULSE_PERF=1 swift test -c release --filter OverheadTests 2>&1 | grep -E "OVERHEAD|Test run|✘"

clean-ci:
	rm -rf .build/ci-logs

# Renders the real SwiftUI components and rebuilds the design-system page (site/ and the docs folder copy).
DOCS_DESIGN := /Volumes/Elvis Obi - Mac Extended/Tokone/docs/design-system
design-site:
	swift build --product pulse-design-render
	rm -rf .build/design-render && .build/debug/pulse-design-render .build/design-render
	python3 -I scripts/build-design-site.py .build/design-render site design/screens
	rm -rf "$(DOCS_DESIGN)" && cp -R site/design-system "$(DOCS_DESIGN)"
	@echo "Deploy: cd site && vercel deploy --prod --scope obileonardos-projects"

# The signed Pulse.app bundle (RELEASE_AND_CI §1–2): pinned XcodeGen, then xcodebuild. Output: build/DerivedData/Build/Products/Debug/Pulse.app
app:
	scripts/bootstrap.sh
	.tools/xcodegen/bin/xcodegen --quiet
	xcodebuild -project Pulse.xcodeproj -scheme PulseMac -configuration Debug -derivedDataPath build/DerivedData build -quiet
	codesign --verify --deep --strict build/DerivedData/Build/Products/Debug/Pulse.app
	@echo "Built and verified: build/DerivedData/Build/Products/Debug/Pulse.app"
