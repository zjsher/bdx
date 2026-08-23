.PHONY: patch minor major release help test

help:
	@echo "Release workflow:"
	@echo "  make patch                  # bump x.y.Z+1"
	@echo "  make minor                  # bump x.Y+1.0"
	@echo "  make major                  # bump X+1.0.0"
	@echo "  make release                # print current version"
	@echo "  make release VERSION=1.2.3  # set exact version"
	@echo ""
	@echo "Testing:"
	@echo "  make test                   # validate the slim Beads-native plugin"

patch minor major:
	@./dev/release.sh $@

release:
	@if [ -n "$(VERSION)" ]; then \
		./dev/release.sh set "$(VERSION)"; \
	else \
		./dev/release.sh current; \
	fi

test:
	@bash dev/test-native-plugin.sh
