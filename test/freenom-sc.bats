#!/usr/bin/env bats

load 'bats-support/load'
load 'bats-assert-1/load'

# variables

script="/usr/local/bin/freenom.sh"
config="/usr/local/etc/freenom.conf"

setup() {
  source $config
  debug=0
}

debug=0 

@test "script: $script" {}
@test "config: $config" {} 

@test "$(date '+%F %H:%M:%S') shellcheck -x freenom.sh" {
  run shellcheck -x $script
  #[ "$status" -ne 0 ]
  assert_output ""
  #output=$( run shellcheck -x $script )
  #echo "# DEBUG: status=$status" >&3
  #echo "# DEBUG: output=$output" >&3
}

