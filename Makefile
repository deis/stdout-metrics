SHELL = /bin/bash
GO = go
GOFMT = gofmt -l
GOLINT = golint
GOTEST = ginkgo -r
GOVET = $(GO) vet
GO_FILES = $(wildcard *.go)
GO_PACKAGES = syslogish influx util
GO_PACKAGES_REPO_PATH = $(addprefix $(REPO_PATH)/,$(GO_PACKAGES))

# the filepath to this repository, relative to $GOPATH/src
REPO_PATH = github.com/deis/stdout-metrics

# The following variables describe the containerized development environment
# and other build options
DEV_ENV_IMAGE := quay.io/deis/go-dev:0.11.0
DEV_ENV_WORK_DIR := /go/src/${REPO_PATH}
DEV_ENV_CMD := docker run --rm -v ${CURDIR}:${DEV_ENV_WORK_DIR} -w ${DEV_ENV_WORK_DIR} ${DEV_ENV_IMAGE}
DEV_ENV_CMD_INT := docker run -it --rm -v ${CURDIR}:${DEV_ENV_WORK_DIR} -w ${DEV_ENV_WORK_DIR} ${DEV_ENV_IMAGE}
LDFLAGS := "-s -X main.version=${VERSION}"

BINARY_DEST_DIR = rootfs/opt/stdout-metrics/sbin

DOCKER_HOST = $(shell echo $$DOCKER_HOST)
BUILD_TAG ?= git-$(shell git rev-parse --short HEAD)
SHORT_NAME ?= stdout-metrics
DEIS_REGISTRY ?= ${DEV_REGISTRY}
IMAGE_PREFIX ?= deis

include versioning.mk

SHELL_SCRIPTS = $(wildcard _scripts/*.sh)

build: build-with-container
push: docker-push
install: kube-install
uninstall: kube-delete
upgrade: kube-update

# Allow developers to step into the containerized development environment
dev:
	${DEV_ENV_CMD_INT} bash

# Containerized dependency resolution
bootstrap:
	${DEV_ENV_CMD} glide install

# This is so you can build the binary without using docker
build-binary:
	GOOS=linux GOARCH=amd64 go build -ldflags ${LDFLAGS} -o $(BINARY_DEST_DIR)/stdout-metrics main.go

build: docker-build
push: docker-push

# Containerized build of the binary
build-with-container:
	mkdir -p ${BINARY_DEST_DIR}
	${DEV_ENV_CMD} make build-binary

build-without-container: build-binary
	docker build -t ${IMAGE} rootfs
	docker tag ${IMAGE} ${MUTABLE_IMAGE}


docker-build: build-with-container
	docker build -t ${IMAGE} rootfs
	docker tag ${IMAGE} ${MUTABLE_IMAGE}

clean:
	docker rmi $(IMAGE)

update-manifests:
	sed 's#\(image:\) .*#\1 $(IMAGE)#' manifests/deis-monitor-stdout-rc.yaml > manifests/deis-monitor-stdout-rc.tmp.yaml

test: test-style test-unit

test-style:
	${DEV_ENV_CMD} make style-check

style-check:
# display output, then check
	$(GOFMT) $(GO_PACKAGES) $(GO_FILES)
	@$(GOFMT) $(GO_PACKAGES) $(GO_FILES) | read; if [ $$? == 0 ]; then echo "gofmt check failed."; exit 1; fi
	$(GOVET) $(REPO_PATH) $(GO_PACKAGES_REPO_PATH)
	$(GOLINT) ./...
	shellcheck $(SHELL_SCRIPTS)

test-unit:
	${DEV_ENV_CMD} $(GOTEST) $(GO_TESTABLE_PACKAGES_REPO_PATH)

kube-install: update-manifests
	kubectl create -f manifests/deis-monitor-stdout-svc.yaml
	kubectl create -f manifests/deis-monitor-stdout-rc.tmp.yaml

kube-delete:
	kubectl delete -f manifests/deis-monitor-stdout-svc.yaml
	kubectl delete -f manifests/deis-monitor-stdout-rc.yaml

kube-update: update-manifests
	kubectl delete -f manifests/deis-monitor-stdout-rc.tmp.yaml
	kubectl create -f manifests/deis-monitor-stdout-rc.tmp.yaml
