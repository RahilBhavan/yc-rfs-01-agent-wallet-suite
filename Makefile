.PHONY: test reproduce

test:
	@if [ -f foundry.toml ]; then forge test; \
	elif [ -f pyproject.toml ]; then uv run pytest; \
	elif [ -f package.json ]; then npm test; \
	else echo "no test suite yet"; fi

# Runs the suite offline and prints one row per scope case, then the headline (tools/reproduce.py).
reproduce:
	@python3 tools/reproduce.py
