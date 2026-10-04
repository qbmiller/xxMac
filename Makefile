.PHONY: build deploy syncjson

SYNCJSON_VENV := .build/syncjson-venv

$(SYNCJSON_VENV)/.ready: scripts/requirements-syncjson.txt
	python3 -m venv $(SYNCJSON_VENV)
	$(SYNCJSON_VENV)/bin/python -m pip install --disable-pip-version-check -r scripts/requirements-syncjson.txt
	@touch $@

build:
	bash bundle_app.sh

deploy:
	bash publish_dmg.sh

syncjson: $(SYNCJSON_VENV)/.ready
	$(SYNCJSON_VENV)/bin/python scripts/syncjson.py
