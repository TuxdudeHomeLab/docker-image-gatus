# syntax=docker/dockerfile:1

ARG BASE_IMAGE_NAME
ARG BASE_IMAGE_TAG

ARG GO_IMAGE_NAME
ARG GO_IMAGE_TAG
FROM ${GO_IMAGE_NAME}:${GO_IMAGE_TAG} AS builder

ARG GATUS_VERSION

COPY scripts/start-gatus.sh /scripts/
COPY patches /patches

# hadolint ignore=DL4006,SC3040,SC3009
RUN \
    set -E -e -o pipefail \
    && export HOMELAB_VERBOSE=y \
    && homelab install git patch \
    && mkdir -p /root/gatus-build \
    # Download gatus repo. \
    && homelab download-git-repo \
        https://github.com/TwiN/gatus \
        ${GATUS_VERSION:?} \
        /root/gatus-build \
    && pushd /root/gatus-build \
    # Apply the patches. \
    && (find /patches -iname *.diff -print0 | sort -z | xargs -0 -r -n 1 patch -p2 -i) \
    # Build Gatus. \
    && go mod tidy \
    && CGO_ENABLED=0 GOOS=linux go build -a . \
    && popd \
    # Copy the build artifacts. \
    && mkdir -p /output/{bin,scripts,configs} \
    && cp /root/gatus-build/gatus /output/bin \
    && cp /root/gatus-build/config.yaml /output/configs \
    && cp /scripts/* /output/scripts

FROM ${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG}

ARG USER_NAME
ARG GROUP_NAME
ARG USER_ID
ARG GROUP_ID
ARG GATUS_VERSION

# hadolint ignore=DL4006,SC2086,SC3009
RUN --mount=type=bind,target=/gatus-build,from=builder,source=/output \
    set -E -e -o pipefail \
    && export HOMELAB_VERBOSE=y \
    # Create the user and the group. \
    && homelab add-user \
        ${USER_NAME:?} \
        ${USER_ID:?} \
        ${GROUP_NAME:?} \
        ${GROUP_ID:?} \
        --create-home-dir \
    && mkdir -p /opt/gatus-${GATUS_VERSION:?}/bin /data/gatus/{config,data} \
    && cp /gatus-build/bin/gatus /opt/gatus-${GATUS_VERSION:?}/bin \
    && cp /gatus-build/configs/config.yaml /data/gatus/config/config.yaml \
    && ln -sf /opt/gatus-${GATUS_VERSION:?} /opt/gatus \
    && ln -sf /opt/gatus/bin/gatus /opt/bin/gatus \
    # Copy the start-gatus.sh script. \
    && cp /gatus-build/scripts/start-gatus.sh /opt/gatus/ \
    && ln -sf /opt/gatus/start-gatus.sh /opt/bin/start-gatus \
    # Set up the permissions. \
    && chown -R ${USER_NAME:?}:${GROUP_NAME:?} \
        /opt/gatus-${GATUS_VERSION:?} \
        /opt/gatus \
        /opt/bin/{gatus,start-gatus} \
        /data/gatus \
    # Clean up. \
    && homelab cleanup

# Expose the TLS port used by Gatus.
EXPOSE 4443

HEALTHCHECK \
    --start-period=15s --interval=30s --timeout=3s \
    CMD homelab healthcheck-service https://localhost:4443/

ENV USER=${USER_NAME}
USER ${USER_NAME}:${GROUP_NAME}
WORKDIR /home/${USER_NAME}

CMD ["start-gatus"]
STOPSIGNAL SIGTERM
