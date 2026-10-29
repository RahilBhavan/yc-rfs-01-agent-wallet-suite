.PHONY: test reproduce

test:
	@if [ -f foundry.toml ]; then forge test; \
	elif [ -f pyproject.toml ]; then uv run pytest; \
	elif [ -f package.json ]; then npm test; \
	else echo "no test suite yet"; fi

reproduce:
	@echo "headline not measured yet: replace this target with the command that prints it" >&2; exit 1
