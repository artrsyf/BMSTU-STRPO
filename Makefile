IMAGE ?= drivingschool-simodo
CONTAINER ?= drivingschool-simodo-local
PROD_BASE_URL ?= http://185.221.215.236:2021/driving

.PHONY: help build run stop restart parse demo test prod-demo prod-test logs ps clean

help:
	@echo "Targets:"
	@echo "  make build      Build local SIMODO Docker image"
	@echo "  make run        Start local services on 8081, 8082, 8083"
	@echo "  make stop       Stop local container"
	@echo "  make restart    Restart local services"
	@echo "  make parse      Parse all s-script files"
	@echo "  make demo       Run local curl demo scenario"
	@echo "  make test       Run local parse + services + smoke check"
	@echo "  make prod-demo  Run prod curl demo scenario"
	@echo "  make prod-test  Run prod smoke check"
	@echo "  make logs       Show local SIMODO logs"

build:
	docker build -t $(IMAGE) .

run:
	sh test/00-run-local

stop:
	docker rm -f $(CONTAINER) >/dev/null 2>&1 || true

restart: stop run

parse: build
	docker run --rm -v "$$(pwd)":/workspace $(IMAGE) sh -lc 'find /workspace/src -name "*.s-script" -print | while read f; do simodo-parse -G /usr/share/simodo/grammar "$$f" >/tmp/parse.out 2>&1 || { echo PARSE_FAIL:$$f; cat /tmp/parse.out; exit 1; }; done; echo OK'

demo:
	sh test/99-demo-flow

test: parse restart
	sh test/98-smoke-check

prod-demo:
	BASE_URL="$(PROD_BASE_URL)" sh test/97-prod-demo-flow

prod-test:
	BASE_URL="$(PROD_BASE_URL)" sh test/96-prod-smoke-check

logs:
	docker exec $(CONTAINER) sh -lc 'cat /tmp/base.log /tmp/students.log /tmp/training.log /tmp/exams.log'

ps:
	docker ps --filter name=$(CONTAINER)

clean: stop
	docker rm -f drivingschool-simodo-prod-layout >/dev/null 2>&1 || true
