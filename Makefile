.PHONY: build test clean cli integration app run-app

build:
	swift build

test:
	swift test

cli:
	swift run cloudupsnap-cli $(ARGS)

integration:
	CLOUDUPSNAP_INTEGRATION=1 swift test

clean:
	swift package clean
	rm -rf .build

app:
	./scripts/bundle.sh

run-app: app
	open "build/Cloudup Snap.app"
