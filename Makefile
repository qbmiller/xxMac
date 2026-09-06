.PHONY: build deploy

build:
	bash bundle_app.sh

deploy:
	bash publish_dmg.sh
