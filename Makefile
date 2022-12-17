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

.PHONY: all clean distclean install uninstall docker

install:

ifeq ("$(wildcard $(CONF))","")
	$(error ERROR: Installation File "$(CONF)" not found)
endif
ifeq ("$(wildcard $(SCRIPT))","")
	$(error ERROR: Installation File "$(SCRIPT)" not found)
endif
ifeq ("$(EXISTCONF)", "0")
	$(shell install -C -m 644 -o root -g $(GROUP) $(CONF) $(CONFDIR))
	$(info Remember to edit "$(CONF)" and set your email and password)
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
    ifeq ("$(wildcard $(SYSDDIR)/freenom-*)","")
	$(info To schedule domain renewals and updates, use these commands:)
	$(info - systemctl enable --now freenom-renew-all.timer)
	$(info - systemctl enable --now freenom-update@example.tk.timer)
	$(info - systemctl enable --now freenom-update@mysubdom.example.tk.timer)
	$(info $() $() * replace 'example.tk' and/or 'mysubdom' with your domain)
    endif
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
ifneq ("$(wildcard $(CRONDIR)/freenom)","")
	$(shell rm $(CRONDIR)/freenom)
endif

define DOCKERFILE_DEBIAN
FROM debian:stable-slim
ARG DEBIAN_FRONTEND=noninteractive
ARG DEBCONF_NOWARNINGS="yes"
COPY freenom.sh /usr/local/bin/
COPY freenom.conf /usr/local/etc/
RUN apt-get -yq update && apt-get -yq install --no-install-recommends curl ca-certificates bind9-dnsutils && rm -rf /var/lib/apt/lists/*
USER nobody
ENTRYPOINT [ "/usr/local/bin/freenom.sh" ]
endef
define DOCKERFILE_ALPINE
FROM alpine:latest
COPY freenom.sh /usr/local/bin/
COPY freenom.conf /usr/local/etc/
RUN apk update && apk add --no-cache bash curl ca-certificates bind-tools
USER nobody
ENTRYPOINT [ "/usr/local/bin/freenom.sh" ]
endef
export DOCKERFILE_DEBIAN
export DOCKERFILE_ALPINE

docker:

ifeq ("$(wildcard $(CONF))","")
	$(error ERROR: Installation File "$(CONF)" not found)
endif
ifeq ("$(wildcard $(SCRIPT))","")
	$(error ERROR: Installation File "$(SCRIPT)" not found)
endif
	@echo "$$DOCKERFILE_DEBIAN" | docker build -t freenom-script:latest -f- .
	@echo "$$DOCKERFILE_ALPINE" | docker build -t freenom-script:alpine -f- .

all: install
clean: uninstall
distclean: uninstall

