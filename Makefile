-include .env
# Default var values
ENV ?=development
ROOT_DIR :=$(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
PROJECT :=$(shell basename $(ROOT_DIR))
RESTART_FLAG ?= docker.restart_required
LOG_LEVEL ?= info

services ?=main
types ?=integration,control,aggregation
#systems ?=datadog

args += --environment=${ENV}
args += --update-flag=${RESTART_FLAG}
args += --log-level=${LOG_LEVEL}

# Development specific additions
ifeq "$(ENV)" "development"
    services := ${services},development
endif

# Production specific additions
ifeq "$(ENV)" "production"
    systems ?=datadog
endif

# Add available options to $args
ifdef services
    args += --service=${services}
endif

ifdef types
    args += --service-type=${types}
endif

ifdef systems
    args += --service-system=${systems}
endif

ifdef exclude
    args += --exclude=${exclude}
endif

.PHONY: help generate docker-compose.yml delploy down clean-volumes clean-dirs clean-compose redis-cli

help:
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

up: deploy ## synonym for deploy target

docker-compose.yml: ## Generate docker-compose.yml file only
	@echo Generating $(ROOT_DIR)/docker-compose.yml file...
	docker run --rm -v $(ROOT_DIR):/repo --entrypoint /bin/bash deriv/myriad -c 'cd /repo && apt update && apt install -y gcc && cpanm -n -q --installdeps . && bin/generate-docker-compose.pl ${args}'
    
deploy: generate ## Generate, build and deploy on update only
ifneq ("$(wildcard ${RESTART_FLAG})","")
	docker-compose build
#    docker-compose up -d
	rm ${RESTART_FLAG}
	@echo updated
else
	@echo all up todate!
endif

generate: docker-compose.yml ## Generate needed config
	@echo Done

restart: ## restart services
	docker-compose restart

logs:  ## follow logs for services
	docker-compose logs --tail=50 -f

down: ## bring down and stop services
	docker-compose down --remove-orphans
clean-volumes: ## remove created volumes (Complete data removal)
	docker volume ls | grep ${PROJECT} | awk '{print $$2}' | xargs docker volume rm 
clean-compose: ## remove generated docker-compose.yml file
	rm -f docker-compose.yml
clean-dirs: ## remove created directories that hold containers files and environment
	rm -rf container_*
clean-all: down clean-volumes clean-dirs clean-compose  ## disable services and remove everything

redis-cli: which ?= main
redis-cli: node ?= 0
redis-cli: ## redis-cli for any needed instance. (which=name_of_redis  node=instance)
	docker exec -it ${PROJECT}_support-redis-${which}-${node}_1 redis-cli
redis-cluster-rejoin: ## rejoin redis cluster nodes
	docker run --rm -v $(ROOT_DIR):/repo --entrypoint /bin/bash --network codensmoke_support-redis-main deriv/myriad -c '/repo/bin/redis-cluster-rejoin.pl'

sqitch: ## Sqitch container to executing a $cmd on a $db. e.g. `make sqitch db=payout cmd=status`
	test -n "${cmd}"
	test -n "${db}"
	docker run --rm --network ${PROJECT}_support-postgresql -v ${ROOT_DIR}:/repo -w /repo/service/support/postgresql/${db} sqitch/sqitch ${cmd}

sqitch-init: ## Sqitch initialize a support postgresql database. e.g. `make sqitch-init db=payout password=change_me
	test -n "${db}"
	test -n "${password}"
ifeq ("$(wildcard service/support/postgresql/${db}/sqitch.conf)","")
	$(MAKE) sqitch cmd="init ${db} --uri https://github.com/deriv-enterprise/${PROJECT}/tree/master/service/support/postgresql/${db} --engine pg --top-dir /repo/service/support/postgresql/${db} --target db:pg://postgres:${password}@support-postgresql-${db}-0:5432/${db}"
else
	@echo already initialized!
endif

# add redis cluster fix

