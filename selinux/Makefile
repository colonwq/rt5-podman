# SELinux policy module for RT5 (Postfix pipe / Podman)
# Builds rt5.pp from total.te (module rt5, version 1.0)

MODULE   := rt5
VERSION  := 1.0
TE_FILE  := total.te
MOD_FILE := $(MODULE).mod
PP_FILE  := $(MODULE).pp

.PHONY: all install clean

all: $(PP_FILE)

$(PP_FILE): $(TE_FILE)
	checkmodule -M -m -o $(MOD_FILE) $(TE_FILE)
	semodule_package -o $(PP_FILE) -m $(MOD_FILE)

install: $(PP_FILE)
	semodule -i $(PP_FILE)

clean:
	rm -f $(MOD_FILE) $(PP_FILE)
