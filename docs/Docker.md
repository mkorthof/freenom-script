# Docker

<https://github.com/mkorthof/freenom-script/pkgs/container/freenom_script>

## Debian

ghcr.io/mkorthof/freenom-script:latest

> default image
> debian stable slim amd64
> size: 127MB

## Alpine


ghcr.io/mkorthof/freenom-script:alpine
> alternative smaller image
> alpine latest x86_64
> size: 15MB

## Run

To list domains, run:

`docker run --rm --env freenom_email="you@example.com" --env freenom_passwd="yourpassword" ghcr.io/mkorthof/freenom-script -l`

Use a config file:

`docker run --rm --volume $(pwd)/freenom.conf:/usr/local/etc/freenom.conf ghcr.io/mkorthof/freenom-script -l`

## Build your own image

Run: `make docker`

Creates "freenom-script:latest" and "freenom-script:alpine".

To test, try one of the 'docker run' commands above.
