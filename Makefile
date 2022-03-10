INSTALL_DIR=$(shell go env GOPATH)/bin
GOOS=$(shell go env GOOS)
GOARCH=$(shell go env GOARCH)

bin:
	goreleaser build --single-target --snapshot --rm-dist
.PHONY: bin

build: site/out bin
.PHONY: build

# Runs migrations to output a dump of the database.
database/dump.sql: $(wildcard database/migrations/*.sql)
	go run database/dump/main.go

# Generates Go code for querying the database.
database/generate: fmt/sql database/dump.sql database/query.sql
	cd database && sqlc generate && rm db_tmp.go
	cd database && gofmt -w -r 'Querier -> querier' *.go
	cd database && gofmt -w -r 'Queries -> sqlQuerier' *.go
.PHONY: database/generate

docker/image/coder: build
	cp ./images/coder/run.sh ./dist/coder_$(GOOS)_$(GOARCH)
	docker build --network=host -t us-docker.pkg.dev/coder-blacktriangle-dev/ci/coder:latest -f images/coder/Dockerfile ./dist/coder_$(GOOS)_$(GOARCH)
.PHONY: docker/build

fmt/prettier:
	@echo "--- prettier"
# Avoid writing files in CI to reduce file write activity
ifdef CI
	cd site && yarn run format:check
else
	cd site && yarn run format:write
endif
.PHONY: fmt/prettier

fmt/sql: ./database/query.sql
	npx sql-formatter \
		--language postgresql \
		--lines-between-queries 2 \
		./database/query.sql \
		--output ./database/query.sql
	sed -i 's/@ /@/g' ./database/query.sql

fmt: fmt/prettier fmt/sql
.PHONY: fmt

gen: database/generate peerbroker/proto provisionersdk/proto provisionerd/proto
.PHONY: gen

install: bin
	@echo "--- Copying from bin to $(INSTALL_DIR)"
	cp -r ./dist/coder_$(GOOS)_$(GOARCH) $(INSTALL_DIR)
	@echo "-- CLI available at $(shell ls $(INSTALL_DIR)/coder*)"
.PHONY: install

peerbroker/proto: peerbroker/proto/peerbroker.proto
	protoc \
		--go_out=. \
		--go_opt=paths=source_relative \
		--go-drpc_out=. \
		--go-drpc_opt=paths=source_relative \
		./peerbroker/proto/peerbroker.proto
.PHONY: peerbroker/proto

provisionerd/proto: provisionerd/proto/provisionerd.proto
	protoc \
		--go_out=. \
		--go_opt=paths=source_relative \
		--go-drpc_out=. \
		--go-drpc_opt=paths=source_relative \
		./provisionerd/proto/provisionerd.proto
.PHONY: provisionerd/proto

provisionersdk/proto: provisionersdk/proto/provisioner.proto
	protoc \
		--go_out=. \
		--go_opt=paths=source_relative \
		--go-drpc_out=. \
		--go-drpc_opt=paths=source_relative \
		./provisionersdk/proto/provisioner.proto
.PHONY: provisionersdk/proto

site/out: 
	./scripts/yarn_install.sh
	cd site && yarn build
	cd site && yarn export
	# Restores GITKEEP files!
	git checkout HEAD site/out
.PHONY: site/out

snapshot: 
	goreleaser release --snapshot --rm-dist
.PHONY: snapshot

template/%s:

	# Embed Terraform for each platform.