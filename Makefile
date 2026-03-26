-include $(HOME)/.archr/options

export OFFICIAL

all: world

system:
	./scripts/image

release:
	./scripts/image release

image:
	./scripts/image mkimage

noobs:
	./scripts/image noobs

clean:
	./scripts/makefile_helper --clean

distclean:
	./scripts/makefile_helper --distclean

src-pkg:
	tar cvJf sources.tar.xz sources

docs:
	./tools/foreach './scripts/clean emulators && ./scripts/build emulators'

world: RK3326

kconfig-olddefconfig-%:
	DEVICE=$* ./tools/adjust_kernel_config olddefconfig

kconfig-menuconfig-%:
	DEVICE=$* ./tools/adjust_kernel_config menuconfig

RK3326:
	unset DEVICE_ROOT
	OFFICIAL=$(if $(filter y yes Y YES 1,$(OFFICIAL)),yes,) PROJECT=ArchR DEVICE=RK3326 ARCH=arm ./scripts/build_distro
	OFFICIAL=$(if $(filter y yes Y YES 1,$(OFFICIAL)),yes,) PROJECT=ArchR DEVICE=RK3326 ARCH=aarch64 ./scripts/build_distro

update:
	PROJECT=ArchR DEVICE=RK3326 ARCH=aarch64 ./scripts/update_packages

package:
	./scripts/build ${PACKAGE}

package-clean:
	./scripts/clean ${PACKAGE}

## Docker builds - overview
# docker-* commands just wire up docker to call the normal make command via docker
# For example: make docker-RK3326 will use docker to call: make RK3326
# All variables are scoped to docker-* commands to prevent weird collisions/behavior with non-docker commands

docker-%: DOCKER_IMAGE := "archr-build:latest"

# DOCKER_WORK_DIR is the directory in the Docker image - it is set to /work by default
#   Anytime this directory changes, you must run `make clean` similarly to moving the distribution directory
docker-%: DOCKER_WORK_DIR := $(shell if [ -n "${DOCKER_WORK_DIR}" ]; then echo ${DOCKER_WORK_DIR}; else echo "$$(pwd)" ; fi)

# ${HOME}/.archr/options is a global options file containing developer and build settings.
docker-%: GLOBAL_SETTINGS := $(shell if [ -f "${HOME}/.archr/options" ]; then echo "-v \"${HOME}/.archr/options:${HOME}/.archr/options\""; else echo ""; fi)

# LOCAL_SSH_KEYS_FILE is a variable that contains the location of the authorized keys file for development build use.  It will be mounted into the container if it exists.
docker-%: LOCAL_SSH_KEYS_FILE := $(shell if [ -n "${LOCAL_SSH_KEYS_FILE}" ]; then echo "-v \"${LOCAL_SSH_KEYS_FILE}:${LOCAL_SSH_KEYS_FILE}\""; else echo ""; fi)

# EMULATIONSTATION_SRC is a variable that contains the location of local emulationstation source code. It will be mounted into the container if it exists.
docker-%: EMULATIONSTATION_SRC := $(shell if [ -n "${EMULATIONSTATION_SRC}" ]; then echo "-v \"${EMULATIONSTATION_SRC}:${EMULATIONSTATION_SRC}\""; else echo ""; fi)

# UID is the user ID of current user - ensures docker sets file permissions properly
docker-%: UID := $(shell id -u)

# GID is the main user group of current user - ensures docker sets file permissions properly
docker-%: GID := $(shell id -g)

# PWD is 'present working directory' and passes through the full path to current dir to docker (becomes 'work')
docker-%: PWD := $(shell pwd)

# Command to use (either `docker` or `podman`)
docker-%: DOCKER_CMD:= $(shell if which docker 2>/dev/null 1>/dev/null; then echo "docker"; elif which podman 2>/dev/null 1>/dev/null; then echo "podman"; fi)

# Podman requires some extra args (`--userns=keep-id` and `--security-opt=label=disable`).  Set those args if using podman
#   Make sure that docker isn't just an alias for podman
docker-%: PODMAN_ARGS:= $(shell if echo "$$(docker --version 2>/dev/null || podman --version 2>/dev/null )" | grep podman 1>/dev/null ; then echo "--userns=keep-id --security-opt=label=disable -v /proc/mounts:/etc/mtab"; fi)

# Launch docker as interactive if this is an interactive shell (allows ctrl-c for manual and running non-interactive - aka: build server)
docker-%: INTERACTIVE=$(shell [ -t 0 ] && echo "-it")

# By default pass through anything after `docker-` back into `make`
docker-%: COMMAND=make $*

# If the user issues a `make docker-shell` just start up bash as the shell to run commands
docker-shell: COMMAND=bash

# Command: builds and saves a docker builder image locally.
# The build user must also be a member of the "docker" group.
docker-image-build:
	$(DOCKER_CMD) buildx create --use
	$(DOCKER_CMD) buildx build --tag $(DOCKER_IMAGE) --platform linux/amd64 --load .

# Command: pulls latest docker image from dockerhub.  This will *replace* locally built version.
docker-image-pull:
	$(DOCKER_CMD) pull $(DOCKER_IMAGE)

# Wire up docker to call equivalent make files using % to match and $* to pass the value matched by %
docker-%:
	./scripts/get_env > .env
	BUILD_DIR="$(DOCKER_WORK_DIR)" $(DOCKER_CMD) run $(PODMAN_ARGS) $(INTERACTIVE) --init --env-file .env --rm --user $(UID):$(GID) $(GLOBAL_SETTINGS) $(LOCAL_SSH_KEYS_FILE) $(EMULATIONSTATION_SRC) -v "$(PWD)":"$(DOCKER_WORK_DIR)" -v /tmp:/tmp -w "$(DOCKER_WORK_DIR)" $(DOCKER_EXTRA_OPTS) $(DOCKER_IMAGE) $(COMMAND)
