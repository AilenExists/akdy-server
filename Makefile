COMPOSE = docker compose --env-file ./.secrets/.env

up:
	$(COMPOSE) up -d
build:
	$(COMPOSE) build
up-build:
	$(COMPOSE) up -d --build
config:
	$(COMPOSE) config
ps:
	$(COMPOSE) ps
down:
	$(COMPOSE) down
delete:
	$(COMPOSE) down -v --remove-orphans