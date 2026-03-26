.PHONY: up down logs build reset infra services test

# Start infrastructure only
infra:
	docker compose up -d

# Start infrastructure + application services
up:
	docker compose -f docker-compose.yml -f docker-compose.services.yml up -d

# Stop everything
down:
	docker compose -f docker-compose.yml -f docker-compose.services.yml down

# View logs
logs:
	docker compose -f docker-compose.yml -f docker-compose.services.yml logs -f

# Build application services
build:
	docker compose -f docker-compose.yml -f docker-compose.services.yml build

# Reset everything (destroy volumes)
reset:
	docker compose -f docker-compose.yml -f docker-compose.services.yml down -v
	docker compose up -d

# Start only infra (for local dev with npm run start:dev)
dev:
	docker compose up -d
	@echo ""
	@echo "Infrastructure is running:"
	@echo "  PostgreSQL (upload):  localhost:5432"
	@echo "  PostgreSQL (report):  localhost:5433"
	@echo "  DynamoDB Local:       localhost:8000"
	@echo "  RabbitMQ:             localhost:5672 (mgmt: localhost:15672)"
	@echo "  MinIO:                localhost:9000 (console: localhost:9001)"
	@echo ""
	@echo "Run each service with: cd ../hackaton-<service> && npm run start:dev"
