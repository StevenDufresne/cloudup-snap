.PHONY: build test clean cli integration

build:
	swift build

test:
	swift test

cli:
	swift run screenshotter-cli $(ARGS)

integration:
	SCREENSHOTTER_INTEGRATION=1 swift test

clean:
	swift package clean
	rm -rf .build
