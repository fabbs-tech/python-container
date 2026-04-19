# python-container

Container image for the `python` tooling discipline. Python + the
standard CI/dev toolchain (ruff, pyright, pytest, nbstripout,
ipykernel) on Ubuntu 22.04. Sibling of
[`fabbs-tech/jax4090-container`](https://github.com/fabbs-tech/jax4090-container)
— that one carries JAX + CUDA on top, this one stays lean for every
non-JAX python repo.

Built and pushed automatically by `.github/workflows/build.yml` on
every change to `Dockerfile`. Available at:

- `ghcr.io/fabbs-tech/python-container:py3.12` — Python 3.12 (pinned)
- `ghcr.io/fabbs-tech/python-container:py3.13` — Python 3.13 (pinned)
- `ghcr.io/fabbs-tech/python-container:latest` — floats with the SPEC
  0 Python floor (currently 3.12; bumped in lockstep with
  `tooling/methods/python/README.md`)

Consumer repos pin a specific `:pyX.Y` tag before first release; the
floating `:latest` is fine during active development.

## Using in CI

`tooling/ci/workflows/python_test.yml` pulls this image and runs
lint + type-check + tests inside it, mirroring the pattern
`python_jax_test.yml` uses for the JAX image. One-image-many-repos:
the image carries the toolchain, each consumer repo's
`requirements.txt` installs at CI-run time.

## Updating the image

1. Edit `Dockerfile` on a branch, open a PR, merge to `main`.
2. The `paths` filter on `build.yml` includes `Dockerfile` and the
   workflow file itself, so merging triggers a rebuild across every
   version in the matrix. Images land at `:pyX.Y` and (for the SPEC 0
   floor) `:latest`.
3. To stamp a dated snapshot alongside the floating tags: **Actions
   → Build and Push Python Container → Run workflow**, enter an
   `extra_tag` like `2026-04-19`. That produces
   `:2026-04-19-py3.12`, `:2026-04-19-py3.13`.

## Adding a new Python version

Add the version string to `matrix.python` in `build.yml`. The
deadsnakes PPA carries 3.12, 3.13, and subsequent releases on
Ubuntu 22.04, so no base-image bump is needed. Update the `:latest`
conditional in the Compute tags step when the SPEC 0 floor moves.

## Why ghcr.io

Single registry inside the `fabbs-tech` org, GitHub-native auth for
both push (workflow `GITHUB_TOKEN`) and pull (anonymous for public;
`gh auth` token for private). See
[`tooling/dev_notes/decisions/foundation_install_source.md`](https://github.com/fabbs-tech/tooling)
for the broader auth story across the stack.