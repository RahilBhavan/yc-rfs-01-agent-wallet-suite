.PHONY: test test-tools reproduce

test: test-tools
	forge test

test-tools:
	@PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools -p 'test_*.py' -v

# Offline local suite, validated case rows and pinned upstream provenance.
reproduce:
	@PYTHONDONTWRITEBYTECODE=1 python3 tools/reproduce.py
