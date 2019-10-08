#!/usr/bin/env bats

load 'bats-support/load'
load 'bats-assert-1/load'

# variables

script="/usr/local/bin/freenom.sh"
config="/etc/freenom.conf"

setup() {
  source $config
  freenom_email="user@example.com"
  freenom_password="my@#$very;%x_COMPLICATED_pw123"
  debug=0
}

regex_ip='((((([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])))|(((([0-9A-Fa-f]{1,4}:){7}([0-9A-Fa-f]{1,4}|:))|(([0-9A-Fa-f]{1,4}:){6}(:[0-9A-Fa-f]{1,4}|((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){5}(((:[0-9A-Fa-f]{1,4}){1,2})|:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){4}(((:[0-9A-Fa-f]{1,4}){1,3})|((:[0-9A-Fa-f]{1,4})?:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){3}(((:[0-9A-Fa-f]{1,4}){1,4})|((:[0-9A-Fa-f]{1,4}){0,2}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){2}(((:[0-9A-Fa-f]{1,4}){1,5})|((:[0-9A-Fa-f]{1,4}){0,3}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){1}(((:[0-9A-Fa-f]{1,4}){1,6})|((:[0-9A-Fa-f]{1,4}){0,4}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(:(((:[0-9A-Fa-f]{1,4}){1,7})|((:[0-9A-Fa-f]{1,4}){0,5}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:)))(%.+)?))'
debug=0

# get_func: extract function $1 from $script
#   debug and/or test functions:
#     - var   : fn="$(get_func fname)"
#     - shell : bash -cvx "source $config; $fn; declare -f | nl'
#     - out   : output=$( echo "$( bash -c "..." )" )
#     - bats  : assert_output x

get_func() {
  if [ "$debug" -eq 1 ]; then
    echo "# DEBUG: script=$script config=$config \$*=$*" >&3
  fi
  export debug=$debug
  sed -n '/^'"$1"'/,/^}$/p' $script | sed '/^}$/q'
}

get_dns() {
  #source $config
  export freenom_update=ipv="$1"
  export freenom_domain_name="example.tk"
  export freenom_domain_id="1234567890"
  export dnsManagementPage="$( cat $BATS_TEST_DIRNAME/$2 )"
  fn="$(get_func func_getRec)"
  if [ "$debug" -eq 0 ]; then
    output=$( echo "$( bash -c "source $config; $fn; export current_ip="$3"; func_getRec; declare -p recType recName recTTL recValue" )" )
  else
    echo "# DEBUG: stub=$BATS_TEST_DIRNAME/$2" >&3
    echo "# DEBUG: $( bash -cvx "source $config; $fn; export current_ip="$3"; func_getRec; declare -p recType recName recTTL recValue")" >&3
    assert_output x
  fi
}

@test "script: $script" {}
@test "config: $config" {}

@test "func_help" {
  fn="$(get_func func_help)"
  bash -c "$fn; func_help"
}

@test "func_getDomArgs example.tk" { 
  fn="$(get_func func_getDomArgs)"
  bash -c "$fn; func_getDomArgs example.com"
}

@test "func_showResult" { 
  fn="$(get_func func_showResult)"
  bash -c "$fn; func_showResult"
}

@test "func_trimIpCmd" {
  fn="$(get_func func_trimIpCmd; get_func func_randIp)"
  bash -c "source $config; $fn; func_trimIpCmd"
}

@test "func_trimIpCmd func_randIp" {
  export ipRE="$regex_ip"
  if [ -z "$freenom_update_ip_retry" ]; then freenom_update_ip_retry="3"; fi
  fn="$(get_func func_trimIpCmd; get_func func_randIp)"
  while [[ "$output" == "" && "$i" -lt "$freenom_update_ip_retry" ]]; do
    if [ "$debug" -eq 0 ]; then
      output=$( echo "$( bash -c "source $config; $fn; func_trimIpCmd; func_randIp" )" )
    else
      echo "# DEBUG: $( bash -cvx "source $config; $fn; func_trimIpCmd; func_randIp ")" >&3
      assert_output x
    fi
    i=$((i+1))
  done
  assert_output --regexp "$regex_ip"
}


@test "func_getRec ipv4" { 
  get_dns "4" "html/dnsManagement.html" "1.2.3.4"
  assert_output --regexp "=\"A\".*=\"EXAMPLE.TK\".*=\"[0-9]+.*=\"1\.2\.3\.4\""
}

@test "func_getRec ipv6" { 
  get_dns "6" "html/dnsManagement_6.html" "2001:123:0:1:2:3:4:0"
  assert_output --regexp "=\"AAAA\".*=\"EXAMPLE.TK\".*=\"[0-9]+.*=\"2001:123:0:1:2:3:4:0\""
}

@test "func_renewDate" { 
  fn="$(get_func func_renewDate)"
  bash -c "$fn; func_renewDate 0"
}

@test "func_renewDomain" { 
  fn="$(get_func func_renewDomain)"
  bash -c "$fn; func_renewDomain 0"
}
