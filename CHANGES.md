# Changes

_order: latest/newest on top_

- [**20210507**] fixed renew all systemd unit (PR #39 from aeolyus)
- [**20200927**] fixed mistake unsetting a var (#34)
- [**20200918**] fixed installer conf path issue #33
- [**20200815**] fixed ip6 issue #32 and an ipv6check, added email alerts
  - **config changes:**
    - `MTA="/usr/sbin/sendmail"`
    - `RCPTTO="admin@example.tk"`
    - `MAILFROM="Freenom Script <freenom-script@example.com>"`
- [**20200713**] fixed systemd in installer and mistakes in readme (and #31)
- [**20200705**] mainly fixes:
  - fixed ip update on apex record
  - fixed conf path detection
  - fixed (older) curl failing login (#25)
  - fixed missing expirydate (#28)
  - fixed dot in subdomain aka "sub subdomain" (#29)
  - added (test) option: update all domains/records '-a' (#19)
  - improved logging update errors
  - **config changes:**
    - `freenom_http_sleep="3 3"`
    - `freenom_oldcurl_force="0"`
- [**20200312**] added checks for required bins
- [**20200307**] fixed Makefile, installing freenom.sh was disabled
- [**20200128**] fixed escaping special chars in password (#21)
- [**20200127**] fixed domain renewals (#23)
- [**20191127**] always cleanup cookie file
- [**20191125**] update all domains (#19)
  - **config change:** `freenom_update_all="0"`
- [**20191108**] static ip update (#18)
  - **config changes:**
    - `freenom_static_ip=""`
    - `freenom_update_manual="0"`
- [**20191017**] changed default conf path to /usr/local/etc
- [**20191005**] errorUpdateResult is no longer saved to html file
- [**20190931**] added systemd templates (PR #15 from sdcloudt)
- [**20190927**] added installer
- [**20190922**] fixed issue #12 (sdcloudt)
- [**20190920**] changed out dir
  - **config change:** `freenom_out_dir="/var/log/freenom"`
- [**20190920**] added curl retries
  - **config change:** `freenom_http_retry="3"`
- [**20190621**] changed 'cannot renew until' warnings to notices
- [**20190621**] added tests (BATS)
- [**20190621**] added recType check (A or AAAA) for dyndns
- [**20190420**] option to use seperate .conf file
- [**20190420**] option to skip renewal notice details in log
- [**20190420**] option to list existing dns records
- [**20190317**] retry getting current ip
- [**20190317**] handling of existing dns records (ip update)
- [**20190000**] made updating ip optional
- [**20190000**] fixed token
- [**20190000**] added referer url to curl to fix login
- [**20190000**] added logging
- [**20190000**] added domain renewals

More details: `git log --pretty=short --name-only`
