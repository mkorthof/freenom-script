# Optional Overrides

It's possible to change the defaults included in freenom.conf:

## Settings

``` bash
freenom_http_retry="3"        # number of curl retries
freenom_update_force="0"      # [0/1] force ip update, even if unchanged
freenom_update_ttl="3600"     # ttl in sec (changed from 14440 to 3600)
freenom_update_ip_retry="3"   # number of retries to get ip
freenom_update_ip_log="1"     # [0/1] log 'skipped same ip' msg
freenom_renew_log="1"         # [0/1] log renew warnings details
freenom_list_bind="0"         # [0/1] output isc bind zone format
freenom_http_sleep="3 3"      # wait n to n+n secs between http requests
freenom_oldcurl_force="0"     # [0/1] force older curl version support
```

## Actions

``` bash
freenom_update_ip="0"         # [0/1] arg "-u"
freenom_update_manual="0"     # [0/1] arg "-m"
freenom_update_all="0"        # [0/1] arg "-a" (future update, not working yet)
freenom_list="0"              # [0/1] arg "-l"
freenom_list_renewals="0"     # [0/1] args "-l -d"
freenom_list_records="0"      # [0/1] arg "-z"
freenom_renew_domain="0"      # [0/1] arg "-r"
freenom_renew_all="0"         # [0/1] args "-r -a"
```
