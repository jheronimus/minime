# Minime shared packager container.
#
# Multi-arch (linux/arm64, linux/amd64) lightweight container for image
# packaging only — no compilation toolchain, no kernel build deps.
#
# Used by both Alpine and Buildroot targets for the `make image` step:
#   genassets.sh, mkimage.sh, mkupdate.sh

FROM docker.io/library/alpine:3.24.1

RUN apk add --no-cache --no-progress \
	bash \
	curl \
	dosfstools \
	dtc \
	file \
	genimage \
	mtools \
	u-boot-tools \
	unzip \
	xz \
	zip
