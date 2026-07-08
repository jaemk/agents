# Convenience wrappers around the `x` manager and the test harness.
# These delegate to the real tooling; they add no logic of their own.

.PHONY: install check test review-fix

# Install via mind: melds this repo as a source and installs its items.
# Equivalent to running `mind meld .` by hand.
install:
	mind meld . --yes

check:
	./x check

test:
	bash tests/run.sh

# Review one item and apply the suggested fixes in place. Pass the item id:
#   make review-fix NAME=skill:review
review-fix:
	@test -n "$(NAME)" || { echo "usage: make review-fix NAME=<item>  (e.g. NAME=skill:review)" >&2; exit 2; }
	./x review --fix $(NAME)
