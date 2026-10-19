.PHONY: ci ci-contributor build test perf design-site site clean-ci app release backend-test

# Optional local settings (gitignored), e.g. DOCS for the site build. Template: Config/local.mk.example.
-include Config/local.mk

# Every quality gate, one pass/fail summary. Strict: exact toolchain, real signing identity, accounts project configured.
ci:
	@scripts/ci.sh

# The same gates for contributors and hosted CI: any Swift 6 toolchain, ad-hoc signing, Sync off.
ci-contributor:
	@scripts/ci.sh --contributor

build:
	swift build --build-tests -Xswiftc -warnings-as-errors

test:
	swift test

# Helper time budget, enforced on the maintainer's Mac: overhead ≤ 20 ms p95 over 200 release-build runs.
# Fails when the test fails (the grep alone would exit 0).
perf:
	@mkdir -p .build
	@CLEPSO_PERF=1 swift test -c release --filter OverheadTests > .build/perf.log 2>&1; status=$$?; \
	  grep -E "OVERHEAD|Test run|✘" .build/perf.log; exit $$status

clean-ci:
	rm -rf .build/ci-logs

# Renders the real SwiftUI components and rebuilds the design-system page (site/ and a copy in $(DOCS)).
# Needs DOCS: the planning documents folder with ROADMAP.md and ARCHITECTURE.md (set it in Config/local.mk).
DOCS_DESIGN = $(DOCS)/design-system
design-site:
	$(if $(strip $(DOCS)),,$(error DOCS is not set: add DOCS = <planning docs folder> to Config/local.mk))
	swift build --product clepso-design-render
	rm -rf .build/design-render && .build/debug/clepso-design-render .build/design-render
	python3 -I scripts/build-design-site.py .build/design-render site design/screens
	python3 -I scripts/build-site.py site "$(DOCS)" design/screens
	rm -rf "$(DOCS_DESIGN)" && cp -R site/design-system "$(DOCS_DESIGN)"

# The documentation website (Overview, Progress, Metrics, Architecture, Screens, Changelog, Design system).
site: design-site

# Clepso.app: pinned XcodeGen, then xcodebuild. Signed ad hoc unless Config/Signing.local.xcconfig names an identity.
# Output: build/DerivedData/Build/Products/Debug/Clepso.app
app:
	scripts/bootstrap.sh
	.tools/xcodegen/bin/xcodegen --quiet
	@# Xcode never removes a file a build no longer produces (pulse-statusline, before the rename): start the bundle afresh.
	rm -rf build/DerivedData/Build/Products/Debug/Clepso.app
	xcodebuild -project Clepso.xcodeproj -scheme ClepsoMac -configuration Debug -derivedDataPath build/DerivedData build -quiet
	codesign --verify --deep --strict build/DerivedData/Build/Products/Debug/Clepso.app
	@echo "Built and verified: build/DerivedData/Build/Products/Debug/Clepso.app"

# Signed, notarised release (docs/RELEASE.md §3): make release TAG=v0.1.0-alpha.1. Output: build/release/<tag>/.
# Stops before notarising (exit 3) until the clepso-notary keychain profile exists. Never tags, pushes or publishes.
release:
	$(if $(strip $(TAG)),,$(error TAG is not set: make release TAG=v0.1.0-alpha.1))
	scripts/release.sh $(TAG)

# Accounts backend: starts the local Supabase database and runs the pgTAP isolation tests in its container.
# Needs Docker; not part of `make ci`, which must run without it.
backend-test:
	cd backend && supabase start -x studio,imgproxy,inbucket,edge-runtime,logflare,vector,supavisor,realtime,storage-api >/dev/null
	docker exec -i supabase_db_clepso psql -U postgres -d postgres -q -t -A < backend/supabase/tests/database/isolation.test.sql | tee .build/backend-test.tap
	@! grep -q '^not ok' .build/backend-test.tap && grep -q '^ok 16' .build/backend-test.tap && echo "BACKEND TESTS PASSED"
