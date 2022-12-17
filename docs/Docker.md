# Docker

## Debian

Default image

<https://github.com/mkorthof/freenom-script/pkgs/container/freenom_script>

> ghcr.io/mkorthof/freenom-script:latest
> debian stable slim amd64
> size: 127MB

## Alpine

Alternative smaller image

<https://github.com/mkorthof/freenom-script/pkgs/container/freenom_script:alpine>

> ghcr.io/mkorthof/freenom-script:alpine
> alpine latest x86_64
> size: 15MB

## Run

To list domains, run:

`docker run --rm --env freenom_email="you@example.com" --env freenom_passwd="yourpassword" ghcr.io/mkorthof/freenom-script -l`

Use a config file:

`docker run --rm --volume $(pwd)/freenom.conf:/usr/local/etc/freenom.conf ghcr.io/mkorthof/freenom-script -l`

## Build your own image

Copy docker build command from GitHub Actions workflow: [.github/workflows/docker.yml](https://github.com/mkorthof/freenom-script/blob/a4957766242a701971e7c4d43908a7687479de72/.github/workflows/docker.yml#L19). Running that HEREDOC from inside repo dir should create an image tagged `freenom-script:latest`. To test, try one of the run commands above.
