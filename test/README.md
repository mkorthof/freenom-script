# Tests (BATS)

Bash Automated Testing System

`git clone https://github.com/bats-core/bats-core`

## Test files

* freenom-args.bats
* freenom-funcs.bats

## Variables

* script="/usr/local/bin/freenom.sh"
* config="/etc/freenom.conf"

## Run

`bats freenom-args.bats`

## Options

filter (e.g. run one test only)

`bats freenom-funcs.bats -f func_getRec`

recursive (TAP)

`bats -r . -t`

`bats -r ./test/freenom* -t`

## Libaries

* `git submodule add https://github.com/ztombol/bats-support test/bats-support`
* `git submodule add https://github.com/jasonkarns/bats-assert-1 test/bats-assert-1`

## Documentation

`git clone https://github.com/ztombol/bats-docs`

* https://opensource.com/article/19/2/testing-bash-bats
* https://softwaretester.info/automate-bash-testing-with-bats/

