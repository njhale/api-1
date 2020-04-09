# kernel-style V=1 build verbosity
ifeq ("$(origin V)", "command line")
  BUILD_VERBOSE = $(V)
endif

ifeq ($(BUILD_VERBOSE),1)
  Q =
else
  Q = @
endif

REPO = github.com/operator-framework/api
BUILD_PATH = $(REPO)/cmd/operator-verify
PKGS = $(shell go list ./... | grep -v /vendor/)
YQ_INTERNAL := $(Q) go run $(MOD_FLAGS) ./vendor/github.com/mikefarah/yq/v2/

.PHONY: help
help: ## Show this help screen
	@echo 'Usage: make <OPTIONS> ... <TARGETS>'
	@echo ''
	@echo 'Available targets are:'
	@echo ''
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

.PHONY: install

install: ## Build & install operator-verify
	
	$(Q)go install \
		-gcflags "all=-trimpath=${GOPATH}" \
		-asmflags "all=-trimpath=${GOPATH}" \
		-ldflags " \
			-X '${REPO}/version.GitVersion=${VERSION}' \
			-X '${REPO}/version.GitCommit=${GIT_COMMIT}' \
		" \
		$(BUILD_PATH)

# Code management.
.PHONY: format tidy clean vendor generate

format: ## Format the source code
	$(Q)go fmt $(PKGS)

tidy: ## Update dependencies
	$(Q)go mod tidy -v

vendor: tidy ## Update vendor directory
	$(Q)go mod vendor 

clean: ## Clean up the build artifacts
	$(Q)rm -rf build

generate: controller-gen  ## Generate code
	$(CONTROLLER_GEN) object:headerFile=./hack/boilerplate.go.txt paths=./...

manifests: controller-gen ## Generate manifests e.g. CRD, RBAC etc
	@# Handle >v1 APIs
	$(CONTROLLER_GEN) crd paths=./pkg/operators/v2alpha1... output:crd:dir=./crds

	@# Handle <=v1 APIs
	$(CONTROLLER_GEN) schemapatch:manifests=./crds output:dir=./crds paths=./pkg/operators/...

	@# Preserve unknown fields on the CSV spec (prevents install strategy from being pruned)
	$(YQ_INTERNAL) w --inplace ./crds/operators.coreos.com_clusterserviceversions.yaml spec.validation.openAPIV3Schema.properties.spec.properties.install.properties.spec.properties.deployments.items.properties.spec.properties.template.properties.metadata.x-kubernetes-preserve-unknown-fields true

	@# Update embedded CRD files.
	@go generate ./crds/...

# Static tests.
.PHONY: test test-unit

test: test-unit ## Run the tests

TEST_PKGS:=$(shell go list ./...)
test-unit: ## Run the unit tests
	$(Q)go test -count=1 -short ${TEST_PKGS}

# Utilities.
.PHONY: controller-gen

controller-gen: vendor ## Find or download controller-gen 
CONTROLLER_GEN=$(Q)go run -mod=vendor ./vendor/sigs.k8s.io/controller-tools/cmd/controller-gen

