# frankenphp-unofficial-newrelic

Unofficial pre-built **New Relic PHP agent extension built with ZTS (Zend Thread Safety)** so it can run on **FrankenPHP** and other thread-safe PHP stacks, installable with [PIE](https://github.com/php/pie).

## Why this exists

The stock New Relic PHP agent targets NTS (non-thread-safe) PHP. **FrankenPHP** uses a ZTS PHP build, so you need an extension compiled accordingly. This repository automates building and publishing that extension.

## Agent source (credit)

The ZTS-capable agent sources come from **[Théophile Diot](https://github.com/theophileds)**’s fork:

**[theophileds/newrelic-php-agent-zts](https://github.com/theophileds/newrelic-php-agent-zts) — branch [`zts-support`](https://github.com/theophileds/newrelic-php-agent-zts/tree/zts-support)**

Thanks to Théophile for maintaining the ZTS work this project relies on.

## Installing with PIE

Pre-built binaries are published for ZTS PHP 8.2+ on Linux glibc (`x86_64`, `arm64`):

```shell
pie install snebes/newrelic-zts
```

PIE only installs `newrelic.so`; it cannot build this extension from source. The **daemon is not included** — install New Relic's official `newrelic-daemon` package and point `newrelic.daemon.location` at it. Configure New Relic as usual (license key, app name, `newrelic.ini`, etc.).

## How it is built

[`Dockerfile.zts-build`](Dockerfile.zts-build) compiles `newrelic.so` inside the official `php:<X.Y>-zts-bookworm` image (the same base FrankenPHP uses), with PCRE linked statically. The resulting extension only depends on libc.

To build locally, run from a checkout of the agent fork:

```shell
docker build . -f /path/to/Dockerfile.zts-build --target package \
  --build-arg PHP_VERSION=8.4 --output type=local,dest=out
```

## CI

[`ci.yaml`](.github/workflows/ci.yaml) runs on pull requests and pushes to `main`. It validates `composer.json` and runs the same [`build.yaml`](.github/workflows/build.yaml) used for releases against a pinned agent version that is known to merge cleanly. Each PHP version × architecture is built, checked to link only libc, and smoke-tested in `dunglas/frankenphp:1-php<X.Y>` with concurrent requests ([`smoke-test.sh`](.github/scripts/smoke-test.sh)). Require the **CI gate** check in branch protection.

## Publishing a release

1. Create and publish a GitHub release tagged with a New Relic agent version (e.g. `v12.11.0`, or the exact upstream tag `v12.11.0.40`).
2. [`release.yaml`](.github/workflows/release.yaml) merges that upstream tag into `zts-support` (failing on merge conflicts), builds each PHP version × architecture, and attaches assets named `php_newrelic-<tag>_php<X.Y>-<arch>-linux-glibc-zts.zip`. It can be re-run for an existing tag via manual dispatch.
3. Packagist picks up the new tag automatically once the repository is [submitted](https://packagist.org/packages/submit) and the GitHub hook is enabled.

Each release also gets a `build-info.json` recording the exact fork commit and upstream tag it was built from.

## Adding a new PHP version to existing releases

When a new PHP minor version ships, run [`backfill.yaml`](.github/workflows/backfill.yaml) manually with the PHP version (e.g. `8.6`) and either specific release tags or `all`. For each release it rebuilds only that PHP version from the sources in its `build-info.json`, smoke-tests it, and uploads the new assets alongside the existing ones. Releases whose agent code does not compile against the new PHP version fail individually; the rest are still published. Use the `-rc` image variant to try a release candidate before the final PHP release (FrankenPHP images usually lag, so only a CLI load check runs until `dunglas/frankenphp:1-php<X.Y>` exists).

Also add the new version to the default `php-versions` list in [`build.yaml`](.github/workflows/build.yaml) so future releases include it.

## License

This repository is licensed under the MIT License — see [`LICENSE`](LICENSE). The New Relic agent is licensed under Apache-2.0; its license and third-party notices are included in each release asset.
