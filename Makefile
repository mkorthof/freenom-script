CONF = freenom.conf
SCRIPT = freenom.sh
SYSDDIR = /etc/systemd/user
CRONDIR = /etc/cron.d
INSTDIR = /usr/local/bin

LISTUNITS := $(shell systemctl list-unit-files --no-legend --no-page "freenom-*" 2>/dev/null|cut -d" " -f1)
ifneq ("$(shell grep ^staff: /etc/group)", "")
  GROUP = staff
else
  GROUP = root
endif
ifneq ("$(LISTUNITS)", "")
  SCHED = systemd
else ifneq ("$(wildcard $(CRONDIR))", "")
  SCHED = cron
endif
EXISTCONF = 0
ifneq ("$(wildcard /etc/$(CONF))", "")
  EXISTCONF = 1
endif

.PHONY: all clean distclean install uninstall test

install:

ifeq ("$(wildcard $(CONF))","")
	$(error ERROR: Installation File \"$(CONF)\" not found)
endif
ifeq ("$(wildcard $(SCRIPT))","")
	$(error ERROR: Installation File \"$(SCRIPT)\" not found)
endif
ifeq ("$(EXISTCONF)", "0")
	install -C -m 644 -o root -g root $(CONF) /etc
	$(info )
	$(info Edit "/etc/$(CONF)" to set your email and password)
else
	$(info File "/etc/$(CONF)" already exists)
endif
ifeq ("$(wildcard $(INSTDIR)/$(SCRIPT))","")
	install -C -m 755 -o root -g $(GROUP) $(SCRIPT) $(INSTDIR)
else
	$(info File "$(INSTDIR)/$(SCRIPT)" already exists)
endif
ifeq ("$(SCHED)", "systemd")
	$(info )
  ifeq ("$(wildcard systemd/*)","")
	$(error ERROR: Installation directory and files \"systemd/*\" not found)
  endif
	install -C -D -m 644 -o root -g root systemd/* $(SYSDDIR)
	systemctl daemon-reload
	$(info To schedule domain renewals and updates, use these commands:)
	$(info * systemd enable --now freenom-renew@example.tk.service)
	$(info * systemd enable --now freenom-renew-all@.service)
	$(info * systemd enable --now freenom-update@example.tk.service)
	$(info )
	$(info + replace example.tk with your domain)
	$(info )
else ifeq ("$(SCHED)", "cron")
  ifeq ("$(wildcard cron.d/freenom)","")
	$(error ERROR: Installation File "cron.d/freenom/*" not found)
  else
	install -C -m 644 -o root -g root cron.d/freenom $(CRONDIR)/freenom
	$(info )
	$(info Edit "$(CRONDIR)/freenom" to schedule domain renewals and updates)
	$(info * replace example.tk with your domain and uncomment line(s))
  endif
	$(info )
	$(info See README.md for details)
	$(info )
endif

uninstall:
ifeq ("$(EXISTCONF)","1")
	rm /etc/$(CONF)
endif
ifneq ("$(wildcard $(INSTDIR)/$(SCRIPT))","")
	rm $(INSTDIR)/$(SCRIPT)
endif
ifeq ("$(SCHED)", "systemd")
  ifneq ("$(wildcard $(SYSDDIR)/freenom-*)","")
	@systemctl disable $(LISTUNITS)
	@cd systemd && for u in *; do \
	  if [ -n "$${u}" ] && [ -e "$(SYSDDIR)/$${u}" ]; then \
	    rm "${SYSDDIR}/$$u"; \
	  fi \
	done
	@systemctl daemon-reload
  endif
else ifeq ("$(SCHED)", "cron")
  ifneq ("$(wildcard $(CRONDIR)/freenom)","")
	rm $(CRONDIR)/freenom
  endif
endif

all: install
clean: uninstall
distclean: uninstall

