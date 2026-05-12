# syntax=docker/dockerfile:1.7
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Pick the Python version at build time. The build workflow drives this
# from a matrix so a single Dockerfile produces py3.12, py3.13, … tags
# without divergent Dockerfile.pyXY files. Default lines up with the
# current SPEC 0 floor (see tooling/methods/python/README.md); bump
# when the floor bumps.
ARG PYTHON_VERSION=3.12

# Python + git for foundation library installs + curl for get-pip.
# libatomic1: pyright downloads its own Node binary (via nodeenv)
# which links libatomic.so.1; without it `pyright --version` crashes
# with "error while loading shared libraries: libatomic.so.1". Same
# finding as jax4090-container — see
# tooling/dev_notes/log/python_jax_phase3_bringup.md finding 3.
# deadsnakes PPA gives us 3.12, 3.13, … on Ubuntu 22.04 without
# waiting for Ubuntu's release cadence.
RUN apt-get update && apt-get install -y --no-install-recommends \
        software-properties-common ca-certificates gnupg \
    && add-apt-repository -y ppa:deadsnakes/ppa \
    && apt-get update && apt-get install -y --no-install-recommends \
        python${PYTHON_VERSION} python${PYTHON_VERSION}-dev python${PYTHON_VERSION}-venv \
        git curl \
        libatomic1 \
    && rm -rf /var/lib/apt/lists/*

# gnupg above: vanilla ubuntu:22.04 ships without gpg-agent, so
# `add-apt-repository ppa:deadsnakes/ppa` fails when trying to import
# the PPA key. jax4090-container gets gpg for free via the
# nvidia/cuda base image, but here we install it explicitly.

# Ubuntu 22.04's apt set can transitively pull python3-pyparsing 2.4.7
# for the system Python 3.10. A consumer requirements.txt that needs
# pyparsing>=3 (matplotlib does) triggers pip's uninstall-then-reinstall
# path on the apt copy and trips a Permission denied on root-owned
# /usr/lib/python3/dist-packages/. Purge preemptively; the dpkg guard
# makes this a no-op if our narrowed apt set (--no-install-recommends
# above) doesn't actually pull it in. Same finding as the sibling
# jax4090-container image's 2026-05-12 fix.
RUN if dpkg -s python3-pyparsing > /dev/null 2>&1; then \
        apt-get purge -y --auto-remove python3-pyparsing; \
    fi

# Make the chosen Python the default `python` and `python3`.
RUN update-alternatives --install /usr/bin/python  python  /usr/bin/python${PYTHON_VERSION} 1 \
 && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1

# Bootstrap pip via get-pip.py — distutils-free path that works for
# every 3.12+ release (apt's python3-pip targets the system 3.10 on
# Ubuntu 22.04 and pulls the wrong distutils for 3.12+).
RUN curl -fsSL https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py \
 && python /tmp/get-pip.py \
 && rm /tmp/get-pip.py

# CI/dev toolchain — every python (and python_jax) project needs these.
# Project-specific deps still install at CI / devcontainer
# postCreateCommand time from each consumer repo's requirements.txt;
# these are the always-present ones so they live in the image and don't
# reinstall per run.
RUN python -m pip install --upgrade pip \
 && python -m pip install \
        ruff \
        pyright \
        pytest \
        nbstripout \
        ipykernel

# Non-root user for devcontainer + CI. Default UID/GID 1000 match the
# typical Linux developer account; VS Code's updateRemoteUserUID remaps
# them at container-start time to the actual host UID, so files written
# into bind-mounted /workspace (especially /workspace/.git) keep host
# ownership. CI uses `--user 1000:1000` for the same reason.
#
# The USER directive is deliberately NOT set: the image still defaults
# to root so ad-hoc `docker run` keeps working, and the dev user is
# selected explicitly by consumers (devcontainer.json `remoteUser`,
# CI `docker run --user`). /usr/local/{lib/pythonX.Y,bin,share} are
# chowned so the dev user can `pip install` project deps at runtime.
# share/ matters because pip-installed packages drop manpages, shell
# completions, and locale data under /usr/local/share/; a write
# rejection there (e.g. fonttools' ttx.1, pulled in transitively by
# matplotlib) aborts the whole pip transaction even though the Python
# files themselves would install fine. Same finding as the sibling
# jax4090-container image's 2026-05-12 fix; cross-referenced in
# tooling/dev_notes/log/jax_container_image_fixes_20260512.md.
ARG DEV_USER=dev
ARG DEV_UID=1000
ARG DEV_GID=1000
RUN groupadd --gid ${DEV_GID} ${DEV_USER} \
 && useradd --uid ${DEV_UID} --gid ${DEV_GID} --create-home --shell /bin/bash ${DEV_USER} \
 && chown -R ${DEV_USER}:${DEV_USER} /usr/local/lib/python${PYTHON_VERSION} /usr/local/bin /usr/local/share

WORKDIR /workspace
