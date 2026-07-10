.PHONY: help transfer clean

help:
	@echo; \
	echo "  Available targets:"; \
	echo; \
	echo "    help     - Show this help message (default)"; \
	echo "    transfer - Run the transfer.sh script"; \
	echo "    clean    - Remove temporary *.json files"; \
	echo

transfer:
	./transfer.sh

clean:
	rm -f *.json
