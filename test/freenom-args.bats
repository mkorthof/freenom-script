#!/usr/bin/env bats

load 'bats-support/load'
load 'bats-assert-1/load'

script="/usr/local/bin/freenom.sh"
config="/usr/local/bin/freenom.conf"

setup() {
  source $config
  freenom_email="user@example.com"
  freenom_password="my@#$very;%x_COMPLICATED_pw123"
}

@test "freenom.sh (no args)" {
  run $script
  [ "$status" -eq 1 ]
  assert_output --partial 'Error: invalid or unknown argument(s), try "freenom.sh -h"'
}

@test "freenom.sh -XXX" {
  run $script -xxx
  [ "$status" -eq 1 ]
  assert_output --partial 'Error: invalid or unknown argument(s), try "freenom.sh -h"'
}

@test "freenom.sh -h" {
  run $script -h
  [ "$status" -eq 0 ]
  assert_output --partial "USAGE:"
}

@test "freenom.sh -c /usr/local/bin/freenom.conf" {
  run $script -c $config
  [ "$status" -eq 0 ]
}

@test "freenom.sh -c /invalid/invalid.conf" {
  run $script -c /invalid/invalid.conf
  [ "$status" -eq 1 ]
  [ "$output" = 'Error: invalid config "/invalid/invalid.conf" specified' ]
}

@test "freenom.sh -i" {
  run $script -i
  [ "$status" -eq 0 ]
  assert_output --regexp "((curl|dig) -(%ipv%|4|6))+"
}

@test "freenom.sh -l" {
  export freenom_domain_name="example.tk"
  export freenom_domain_id="1234567890"
  export dnsManagementPage="$( cat html/dnsManagement.html )"
  export debug=0
  run $script -l
  [ "$status" -eq 0 ]
#assert_output x
#  assert_output --partial "Listing Domains and ID's..."
#  assert_output --regexp "Listing Domains and ID's\.\.\.*
#  assert_output -regexp "Domain: \"example\.tk\" Id: \"[0-9]\""
  assert_output --partial "Domain: \"example.tk\""
}

@test "freenom.sh -l -d" {
  skip
  export freenom_domain_name="example.tk"
  export freenom_domain_id="1234567890"
  export dnsManagementPage="$( cat html/dnsManagement.html )"
  freenom.sh -l -d
  [ "$status" -eq 1 ]
#  assert_output --partial "Listing Domains and ID's with renewal details, this might take a while..."
  assert_output --partial "Domain: \"example.tk\""
}

@test "freenom.sh -z invalid-example-123.tk" {
  run $script -z invalid-example-123.tk
  [ "$status" -eq 1 ]
  assert_output --partial 'Error: Could not find Domain ID for "invalid-example-123.tk"'
}
