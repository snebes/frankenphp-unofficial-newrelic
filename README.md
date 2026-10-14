# frankenphp-unofficial-newrelic

Unofficial pre-built **New Relic PHP agent extension built with ZTS (Zend Thread Safety)** so it can run on **FrankenPHP** and other thread-safe PHP stacks, installable with [PIE](https://github.com/php/pie).

## Why this exists

The stock New Relic PHP agent targets NTS (non-thread-safe) PHP. **FrankenPHP** uses a ZTS PHP build, so you need an extension compiled accordingly. This repository automates building and publishing that extension.

## Agent source (credit)

The ZTS-capable agent sources come from **[Théophile Diot](https://github.com/theophileds)**’s fork:

**[theophileds/newrelic-php-agent-zts](https://github.com/theophileds/newrelic-php-agent-zts) — branch [`zts-support`](https://github.com/theophileds/newrelic-php-agent-zts/tree/zts-support)**

Thanks to Théophile for maintaining the ZTS work this project relies on.

## Installing with PIE

Pre-built binaries are published for ZTS PHP 8.2–8.5 on Linux glibc (`x86_64`, `arm64`):

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

## Publishing a release

1. Create and publish a GitHub release (e.g. tag `v1.0.0`).
2. [`release.yaml`](.github/workflows/release.yaml) builds each PHP version × architecture from the current `zts-support` commit and attaches assets named `php_newrelic-<tag>_php<X.Y>-<arch>-linux-glibc-zts.zip`. It can be re-run for an existing tag via manual dispatch.
3. Packagist picks up the new tag automatically once the repository is [submitted](https://packagist.org/packages/submit) and the GitHub hook is enabled.

## License

This repository is licensed under the MIT License — see [`LICENSE`](LICENSE). The New Relic agent is licensed under Apache-2.0; its license and third-party notices are included in each release asset.
