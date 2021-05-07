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

regex_ip='((((([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])))|(((([0-9A-Fa-f]{1,4}:){7}([0-9A-Fa-f]{1,4}|:))|(([0-9A-Fa-f]{1,4}:){6}(:[0-9A-Fa-f]{1,4}|((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){5}(((:[0-9A-Fa-f]{1,4}){1,2})|:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){4}(((:[0-9A-Fa-f]{1,4}){1,3})|((:[0-9A-Fa-f]{1,4})?:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){3}(((:[0-9A-Fa-f]{1,4}){1,4})|((:[0-9A-Fa-f]{1,4}){0,2}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){2}(((:[0-9A-Fa-f]{1,4}){1,5})|((:[0-9A-Fa-f]{1,4}){0,3}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){1}(((:[0-9A-Fa-f]{1,4}){1,6})|((:[0-9A-Fa-f]{1,4}){0,4}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(:(((:[0-9A-Fa-f]{1,4}){1,7})|((:[0-9A-Fa-f]{1,4}){0,5}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:)))(%.+)?))'

# debug=1

# get_fn: extract function $1 from $script
# to debug and/or test functions:
#   - var   : fn="$(get_fn fname)"
#   - shell : bash -cvx "source $config; $fn; declare -f | nl'
#   - out   : output=$( echo "$( bash -c "..." )" )
#   - bats  : assert_output x

# TODO: 'update_all', setRec

get_fn() {
  if [ "$debug" -eq 1 ]; then
    echo "# DEBUG: script=$script config=$config \$*=$*" >&3
  fi
  export debug=$debug
  sed -n '/^'"$1"'/,/^}$/p' $script | sed '/^}$/q'
}

get_dns() {
  #source $config
  export freenom_update_ipv="$1"
  export freenom_domain_name="example.tk"
  export freenom_domain_id="1234567890"
  export dnsManagementPage="$( zcat $BATS_TEST_DIRNAME/$2 )"
  fn="$(get_fn func_getRec)"
  if [ "$debug" -eq 0 ]; then
    output=$( echo "$( bash -c "source $config; $fn; export currentIp="$3"; func_getRec $freenom_domain_name; declare -p recType recName recTTL recValue" )" )
  else
    echo "# DEBUG: stub=$BATS_TEST_DIRNAME/$2" >&3
    echo "# DEBUG: $( bash -cvx "source $config; $fn; export currentIp="$3"; func_getRec $freenom_domain_name; declare -p recType recName recTTL recValue" )" >&3
    assert_output x
  fi
}

@test "script: $script" {}
@test "config: $config" {}

@test "$(date '+%F %H:%M:%S') func_help" {
  fn="$(get_fn func_help)"
  bash -c "$fn; func_help"
}

@test "$(date '+%F %H:%M:%S') func_getDomainArgs example.tk" { 
  fn="$(get_fn func_getDomainArgs)"
  bash -c "$fn; func_getDomainArgs example.com"
}

@test "$(date '+%F %H:%M:%S') func_showResult" { 
  fn="$(get_fn func_showResult)"
  bash -c "$fn; func_showResult"
}

@test "$(date '+%F %H:%M:%S') func_sortIpCmd" {
  fn="$(get_fn func_sortIpCmd; get_fn func_randIp)"
  bash -c "source $config; $fn; func_sortIpCmd"
}

@test "$(date '+%F %H:%M:%S') func_sortIpCmd func_randIp" {
  export ipRE="$regex_ip"
  if [ -z "$freenom_update_ip_retry" ]; then freenom_update_ip_retry="3"; fi
  fn="$(get_fn func_sortIpCmd; get_fn func_randIp)"
  while [[ "$output" == "" && "$i" -lt "$freenom_update_ip_retry" ]]; do
    if [ "$debug" -eq 0 ]; then
      output=$( echo "$( bash -c "source $config; $fn; func_sortIpCmd; func_randIp" )" )
    else
      echo "# DEBUG: $( bash -cvx "source $config; $fn; func_sortIpCmd; func_randIp ")" >&3
      assert_output x
    fi
    i=$((i+1))
  done
  assert_output --regexp "$regex_ip"
}

@test "$(date '+%F %H:%M:%S') func_getRec ipv4" { 
  get_dns "4" "html/dnsManagement.html.gz" "1.2.3.4"
  assert_output --regexp "=\"A\".*=\"TEST\".*=\"[0-9]+.*=\"1\.2\.3\.4\""
}

@test "$(date '+%F %H:%M:%S') func_getRec ipv6" { 
  get_dns "6" "html/dnsManagement_6.html.gz" "2001:123:0:1:2:3:4:0"
  assert_output --regexp "=\"AAAA\".*=\"TEST\".*=\"[0-9]+.*=\"2001:123:0:1:2:3:4:0\""
}

@test "$(date '+%F %H:%M:%S') func_renewDate" { 
  fn="$(get_fn func_renewDate)"
  bash -c "$fn; func_renewDate 0"
}

@test "$(date '+%F %H:%M:%S') func_renewDomain" { 
  fn="$(get_fn func_renewDomain)"
  bash -c "$fn; func_renewDomain 0"
}
