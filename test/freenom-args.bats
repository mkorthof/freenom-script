#!/usr/bin/env bats

load 'bats-support/load'
load 'bats-assert-1/load'

# variables

script="/usr/local/bin/freenom.sh"
config="/usr/local/etc/freenom.conf"

setup() {
  source $config
  freenom_email="user@example.com"
  freenom_password="my@#$very;%x_COMPLICATED_pw123"
  debug=0
}

debug=0

@test "script: $script" {}
@test "config: $config" {} 

@test "$(date '+%F %H:%M:%S') args freenom.sh (no opts)" {
  run $script
  [ "$status" -eq 1 ]
  assert_output --partial 'Error: invalid or unknown argument(s), try "freenom.sh -h"'
}

@test "$(date '+%F %H:%M:%S') args freenom.sh -XXX" {
  run $script -XXX
  [ "$status" -eq 1 ]
  assert_output --partial 'Error: invalid or unknown argument(s), try "freenom.sh -h"'
}

@test "$(date '+%F %H:%M:%S') args freenom.sh -h" {
  run $script -h
  [ "$status" -eq 0 ]
  assert_output --partial "Usage:"
}

@test "$(date '+%F %H:%M:%S') args freenom.sh -c $config" {
  run $script -c $config
  [ "$status" -eq 0 ]
}

@test "$(date '+%F %H:%M:%S') args freenom.sh -c \"/tmp/spa ces/free nom.conf\"" {
  #skip
  tmpdir="/tmp/spa ces"
  tmpcfg="${tmpdir}/free nom.conf"
  [ ! -d "$tmpdir" ] && mkdir "$tmpdir"
  [ ! -e "$tmpcfg" ] && cp $config "$tmpcfg"
  run bash $script -c "$tmpcfg"
  if [ "$debug" -eq 0 ]; then
    [ "$status" -eq 0 ]
  else
    echo "# DEBUG: ls=$( ls -la "$tmpcfg" )" >&3
    echo "# DEBUG: status=$status" >&3
    echo "# DEBUG: output=$output" >&3
  fi
  [ -e "$tmpcfg" ] && rm "$tmpcfg"
  [ -d "$tmpdir" ] && rmdir "$tmpdir"
}

@test "$(date '+%F %H:%M:%S') args freenom.sh -c /invalid/invalid.conf" {
  #debug=0
  #export debug=1
  run $script -c /invalid/invalid.conf
  [ "$status" -eq 1 ]
  [ "$output" = 'Error: invalid config file "/invalid/invalid.conf" specified' ]
}

@test "$(date '+%F %H:%M:%S') args freenom.sh -c \"/spa ces/in valid.conf\"" {
  debug=0
  run $script -c "/spa ces/in valid.conf"
  if [ "$debug" -eq 0 ]; then
    [ "$status" -eq 1 ]
    [ "$output" = 'Error: invalid config file "/spa ces/in valid.conf" specified' ]
  else
    echo "# DEBUG: output=$output" >&3
  fi
}

@test "$(date '+%F %H:%M:%S') args freenom.sh -i" {
  run $script -i
  [ "$status" -eq 0 ]
  assert_output --regexp "((curl|dig) -(%ipv%|4|6))+"
}

@test "$(date '+%F %H:%M:%S') args freenom.sh -u example.tk -s invalid#subdom" {
  run $script -u example.tk -s invalid#subdom
  [ "$status" -eq 1 ]
  assert_output --partial 'Error: invalid or missing subdomain'
}

@test "$(date '+%F %H:%M:%S') args freenom.sh -l (example.tk)" {
  debug=0
  export debug
  export freenom_domain_name="example.tk"
  export freenom_domain_id="1234567890"
  ##export dnsManagementPage="$( zcat $BATS_TEST_DIRNAME/html/dnsManagement.html.gz )"
  run $script -l
  if [ "$debug" -eq 0 ]; then
    [ "$status" -eq 0 ]
    # assert_output --partial "Listing Domains and ID's..."
    # assert_output --regexp "Listing Domains and ID's\.\.\.*"
    # assert_output --regexp "Domain: \"example\.tk\" Id: \"[0-9]\""
    assert_output --partial 'Domain: "example.tk"'
  else
    ##echo "# DEBUG: stub=$BATS_TEST_DIRNAME/html/dnsManagement.html.gz" >&3
    assert_output x
  fi
}

@test "$(date '+%F %H:%M:%S') args freenom.sh -l -d (example.tk)" {
  # skip
  debug=0
  export debug
  export freenom_domain_name="example.tk"
  export freenom_domain_id="1234567890"
  ##export dnsManagementPage="$( zcat $BATS_TEST_DIRNAME/html/dnsManagement.html.gz )"
  ##export myDomainsPage="$( zcat $BATS_TEST_DIRNAME/html/myDomainsPage.html.gz )"
  run $script -l -d
  if [ "$debug" -eq 0 ]; then
    [ "$status" -eq 1 ]
    assert_output --partial "Listing Domains and ID's with renewal details, this might take a while..."
  else
    ##echo "# DEBUG: stub=$BATS_TEST_DIRNAME/html/dnsManagement.html.gz" >&3
    ##echo "# DEBUG: stub=$BATS_TEST_DIRNAME/html/myDomainsPage.html.gz" >&3
    echo "# DEBUG: status=$status" >&3
    echo "# DEBUG: output=$output" >&3
    #assert_output x
  fi
}

@test "$(date '+%F %H:%M:%S') args freenom.sh -u invalid-example-123.tk" {
  debug=0
  export debug
  run $script -u invalid-example-123.tk
  if [ "$debug" -eq 0 ]; then
    [ "$status" -eq 1 ]
    #assert_output --partial 'Error: Could not find Domain ID for "invalid-example-123.tk"'
  else
    echo "# DEBUG: status=$status" >&3
    echo "# DEBUG: output=$output" >&3
    #assert_output x
  fi
}

@test "$(date '+%F %H:%M:%S') args freenom.sh -u example.tk -s subdom -m 1.2.3.4" {
  debug=0
  export debug
  export freenom_domain_id="1234567890"
  tmpip4="/var/log/freenom/freenom_subdom.example.tk.ip4"
  if [ "$( id -u )" -ne 0 ]; then
    tmpip4="/tmp/freenom_subdom.example.tk.ip4"
  fi
  echo "1.2.3.4" > "$tmpip4"
  run $script -u example.tk -s subdom -m 1.2.3.4
  if [ "$debug" -eq 0 ]; then
    [ "$status" -eq 0 ]
    assert_output --partial 'Update: Skipping "subdom.example.tk" - found same ip "1.2.3.4"'
  else
    echo "# DEBUG: status=$status" >&3
    echo "# DEBUG: output=$output" >&3
    assert_output x
  fi
  [ -e "$tmpip4" ] && rm "$tmpip4"
}

@test "$(date '+%F %H:%M:%S') args freenom.sh -u example.tk -s subdom-stest -m 1.2.3.4" {
  debug=0
  export debug
  export freenom_domain_id="1234567890"
  tmpip4="/var/log/freenom/freenom_subdom-stest.example.tk.ip4"
  if [ "$( id -u )" -ne 0 ]; then
    tmpip4="/tmp/freenom_subdom-stest.example.tk.ip4"
  fi
  echo "1.2.3.4" > "$tmpip4"
  run $script -u example.tk -s subdom-stest -m 1.2.3.4
  if [ "$debug" -eq 0 ]; then
    [ "$status" -eq 0 ]
    assert_output --partial 'Update: Skipping "subdom-stest.example.tk" - found same ip "1.2.3.4"'
  else
    echo "# DEBUG: status=$status" >&3
    echo "# DEBUG: output=$output" >&3
    #assert_output x
  fi
  [ -e "$tmpip4" ] && rm "$tmpip4"
}

@test "$(date '+%F %H:%M:%S') args freenom.sh -z invalid-example-123.tk" {
  # skip
  debug=0
  export debug
  run $script -z invalid-example-123.tk
  if [ "$debug" -eq 0 ]; then
    [ "$status" -eq 1 ]
    #assert_output --partial 'Error: Could not find Domain ID for "invalid-example-123.tk"'
    #assert_output --regexp 'DNS Zone: "invalid-example-123.tk" \(1234567890\).*No records found'
  else
    echo "# DEBUG: status=$status" >&3
    echo "# DEBUG: output=$output" >&3
    #assert_output x
  fi
}
