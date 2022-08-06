# Docker

> ghcr.io/mkorthof/freenom-script:freenom-script
> amd64/linux
> latest: digest: sha256:ed84b6764f8f0ae3b6b28f61a3cc019108be5cc96a57f3454fdf23124e22a20f   size: 1158

## Run

To list domains, run:

`docker run --rm --env freenom_email="you@example.com" --env freenom_passwd="yourpassword" ghcr.io/mkorthof/freenom-script -l`

Or, use a config file:

`docker run --rm --volume $(pwd)/freenom.conf:/usr/local/etc/freenom.confd ghcr.io/mkorthof/freenom-script -l`

## Build your own image

Copy docker build command GitHub Actions workflow: [.github/workflows/docker.yml](https://github.com/mkorthof/freenom-script/blob/a4957766242a701971e7c4d43908a7687479de72/.github/workflows/docker.yml#L19). Running that HEREDOC from repo should create an image tagged `freenom-script:latest`. To test, try on of the run commands above.