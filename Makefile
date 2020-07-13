CONF = freenom.conf
SCRIPT = freenom.sh
SYSDDIR = /lib/systemd/system
CRONDIR = /etc/cron.d
INSTDIR = /usr/local/bin
CONFDIR = /usr/local/etc

ifneq ("$(shell grep ^staff: /etc/group)", "")
  GROUP = staff
else
  GROUP = root
endif
EXISTCRON = 0
ifneq ("$(wildcard /run/systemd/system)", "")
  SCHED = systemd
#  ifneq ("$(wildcard /usr/lib/systemd/system)","")
#    SYSDDIR = /lib/systemd/system
#  else ifneq ("$(wildcard /lib/systemd/system)","")
#    SYSDDIR = /usr/lib/systemd/system
#  endif
  LISTUNITS := $(shell systemctl list-unit-files --no-legend --no-page "freenom-*" 2>/dev/null|cut -d" " -f1)
else ifneq ("$(shell which cron 2>/dev/null)", "")
  EXISTCRON = 1
  SCHED = cron
endif
ifeq ("$(SYSDDIR)", "")
  ifeq ("$(EXISTCRON)", "1")
    SCHED = cron
  else
    $(info No scheduler found (cron/systemd))
  endif
endif
EXISTCONF = 0
ifneq ("$(wildcard /etc/$(CONF))", "")
  CONFDIR = /etc
  EXISTCONF = 1
endif
ifneq ("$(wildcard $(CONFDIR)/$(CONF))", "")
  EXISTCONF = 1
endif

.PHONY: all clean distclean install uninstall

install:

ifeq ("$(wildcard $(CONF))","")
	$(error ERROR: Installation File "$(CONF)" not found)
endif
ifeq ("$(wildcard $(SCRIPT))","")
	$(error ERROR: Installation File "$(SCRIPT)" not found)
endif
ifeq ("$(EXISTCONF)", "0")
	$(shell install -C -m 644 -o root -g root $(CONF) $(CONFDIR))
	$(info Edit "$(CONF)" to set your email and password)
else
	$(info File "$(CONFDIR)/$(CONF)" already exists)
endif
ifeq ("$(wildcard $(INSTDIR)/$(SCRIPT))","")
	$(shell install -C -m 755 -o root -g $(GROUP) $(SCRIPT) $(INSTDIR))
else
	$(info File "$(INSTDIR)/$(SCRIPT)" already exists)
endif

ifeq ("$(SCHED)", "systemd")
  ifeq ("$(wildcard systemd/*)","")
	$(error ERROR: Installation path "systemd/*" not found)
  endif
  ifneq ("$(LISTUNITS)", "")
	$(info Systemd unit files already installed)
  else
	$(shell install -C -D -m 644 -o root -g root systemd/* $(SYSDDIR))
	$(shell systemctl daemon-reload)
	$(info To schedule domain renewals and updates, use these commands:)
	$(info - systemctl enable --now freenom-renew@example.tk.timer)
	$(info - systemctl enable --now freenom-renew-all@.timer)
	$(info - systemctl enable --now freenom-update@example.tk.timer)
	$(info $() $() * replace 'example.tk' with your domain)
  endif
else ifeq ("$(SCHED)", "cron")
  ifeq ("$(wildcard cron.d/freenom)","")
	$(error ERROR: Installation path "cron.d/freenom/*" not found)
  else
	$(shell install -C -m 644 -o root -g root cron.d/freenom $(CRONDIR)/freenom)
	$(info Edit "$(CRONDIR)/freenom" to schedule domain renewals and updates)
	$(info $() $() * replace example.tk with your domain and uncomment line(s))
	$(info See README.md for details)
  endif
endif

uninstall:

ifeq ("$(EXISTCONF)","1")
	$(shell rm $(CONFDIR)/$(CONF))
endif
ifneq ("$(wildcard $(INSTDIR)/$(SCRIPT))","")
	$(shell rm $(INSTDIR)/$(SCRIPT))
endif
ifneq ("$(LISTUNITS)", "")
	$(shell systemctl disable $(LISTUNITS))
endif
ifneq ("$(wildcard $(SYSDDIR)/freenom-*)","")
	@cd systemd && for u in *; do \
	if [ -n "$${u}" ] && [ -e "$(SYSDDIR)/$${u}" ]; then \
	  rm "${SYSDDIR}/$$u"; \
	  fi \
	done
	$(shell systemctl daemon-reload)
endif
#ifneq ("$(wildcard /etc/systemd/user/freenom-*)","")
#	rm -rf /etc/systemd/user/freenom-*
#endif
ifneq ("$(wildcard $(CRONDIR)/freenom)","")
	$(shell rm $(CRONDIR)/freenom)
endif

all: install
clean: uninstall
distclean: uninstall

