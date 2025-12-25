.PHONY: up down build test migrate

up:
	docker-compose up -d

down:
	docker-compose down

build:
	docker-compose build

test:
	docker-compose exec backend pytest

migrate:
	docker-compose exec backend alembic upgrade head
