.PHONY: check update-docs

check:          ## Syntax-check all lib/bash/*.sh and lib/ps/*.ps1 files
	@bash scripts/check.sh

update-docs:    ## Refresh function line numbers and ~NNN counts in CLAUDE.md
	@bash scripts/update-line-numbers.sh
