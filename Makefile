.PHONY: format
format:
	swift format -r -p -i .

.PHONY: lint
lint:
	swift format lint -r -p .

