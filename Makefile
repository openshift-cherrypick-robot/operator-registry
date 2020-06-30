GO := GOFLAGS="-mod=vendor" go
CMDS := $(addprefix bin/, $(shell ls ./cmd | grep -v opm))
OPM := $(addprefix bin/, opm)
SPECIFIC_UNIT_TEST := $(if $(TEST),-run $(TEST),)
PKG := github.com/operator-framework/operator-registry
GIT_COMMIT := $(shell git rev-parse --short HEAD)
OPM_VERSION := $(shell cat OPM_VERSION)
BUILD_DATE := $(shell date -u +'%Y-%m-%dT%H:%M:%SZ')


.PHONY: all
all: clean test build sanity-check

$(CMDS):
	$(GO) build $(extra_flags) -o $@ ./cmd/$(notdir $@)
$(OPM): opm_version_flags=-ldflags "-X '$(PKG)/cmd/opm/version.gitCommit=$(GIT_COMMIT)' -X '$(PKG)/cmd/opm/version.opmVersion=$(OPM_VERSION)' -X '$(PKG)/cmd/opm/version.buildDate=$(BUILD_DATE)'"
$(OPM):
	$(GO) build $(opm_version_flags) $(extra_flags) -o $@ ./cmd/$(notdir $@)

.PHONY: build
build: clean $(CMDS) $(OPM)

.PHONY: static
static: extra_flags=-ldflags '-w -extldflags "-static"'
static: build

.PHONY: unit
unit:
	$(GO) test $(SPECIFIC_UNIT_TEST) -count=1 -v -race ./pkg/...

.PHONY: sanity-check
sanity-check:
	# Build a container with the most recent binaries for this project.
	# Does not include the database, which needs to be added separately.
	docker build -f upstream-builder.Dockerfile -t sanity-container .

	# TODO: add more invocations of the opm binary here

	# serve the container for a second, using the bundles.db in testdata
	docker run --rm -it -v "$(shell pwd)"/pkg/lib/indexer/testdata/:/database sanity-container \
		./bin/opm registry serve --database /database/bundles.db --timeout-seconds 1

.PHONY: image
image:
	docker build .

.PHONY: image-upstream
image-upstream:
	docker build -f upstream-example.Dockerfile .

.PHONY: vendor
vendor:
	$(GO) mod vendor

.PHONY: codegen
codegen:
	protoc -I pkg/api/ --go_out=plugins=grpc:pkg/api pkg/api/*.proto
	protoc -I pkg/api/grpc_health_v1 --go_out=plugins=grpc:pkg/api/grpc_health_v1 pkg/api/grpc_health_v1/*.proto

.PHONY: container-codegen
container-codegen:
	docker build -t operator-registry:codegen -f codegen.Dockerfile .
	docker run --name temp-codegen operator-registry:codegen /bin/true
	docker cp temp-codegen:/codegen/pkg/api/. ./pkg/api
	docker rm temp-codegen

.PHONY: generate-fakes
generate-fakes:
	$(GO) generate ./...

.PHONY: clean
clean:
	@rm -rf ./bin

.PHONY: e2e
e2e:
	$(GO) run github.com/onsi/ginkgo/ginkgo --v --randomizeAllSpecs --randomizeSuites --race ./test/e2e
