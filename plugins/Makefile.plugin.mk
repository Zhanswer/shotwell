
# Generic plug-in Makefile for Shotwell standard plugins.
#
# Requires PLUGIN and SRC_FILES be set to the name of the plugin binary (minus extension) and that 
# the directory is registered in plugins.mk.
#
# To use, include this file in each plug-in directory's Makefile after setting apropriate variables.
# Also be sure that each plug-in has a dummy_main() function to satisfy valac's linkage.
#
# NOTE: This file is called from the cwd of each directory, hence the relative paths should be
# read as such.

VALAC := valac
MAKE_FILES := Makefile ../Makefile.plugin.mk ../plugins.mk
HEADER_FILES := ../shotwell-plugin-dev-1.0.vapi ../shotwell-plugin-dev-1.0.h \
	../shotwell-plugin-dev-1.0.deps

include ../plugins.mk

# automatically include shotwell-plugin-dev-1.0's dependencies
PKGS := $(shell sed ':a;N;$$!ba;s/\n/ /g' ../shotwell-plugin-dev-1.0.deps) $(PKGS)

# automatically include the shotwell-plugin-dev-1.0 package as a local dependency
EXT_PKGS := $(PKGS) 
PKGS := shotwell-plugin-dev-1.0 $(PKGS)

# automatically include the Resources.vala common file
SRC_FILES := ../common/Resources.vala $(SRC_FILES)

CFILES := $(notdir $(SRC_FILES:.vala=.c))
OFILES := $(notdir $(SRC_FILES:.vala=.o))

CFLAGS := `pkg-config --print-errors --cflags $(EXT_PKGS)` -O2 -g -pipe -fPIC -nostdlib \
	-export-dynamic
LDFLAGS := `pkg-config --print-errors --libs $(EXT_PKGS)` $(LDFLAGS)
DEFINES := -D_VERSION='"$(PLUGINS_VERSION)"' -DGETTEXT_PACKAGE='"shotwell"'

all: $(PLUGIN).so

.stamp: $(SRC_FILES) $(MAKE_FILES) $(HEADER_FILES)
	$(VALAC) -g --enable-checking --fatal-warnings --save-temps --compile \
		--vapidir=../ $(foreach pkg,$(PKGS),--pkg=$(pkg)) \
		-X -I../.. -X -fPIC \
		$(foreach dfn,$(DEFINES),-X $(dfn)) \
		$(SRC_FILES)
	@touch .stamp

$(CFILES): .stamp
	@

$(OFILES): %.o: %.c $(CFILES)
	$(CC) -c $(CFLAGS) $(DEFINES) -I../.. $(CFILES)

$(PLUGIN).so: $(OFILES)
	$(CC) $(CFLAGS) $(LDFLAGS) $(OFILES) -I../.. -shared -o $@

.PHONY: cleantemps
cleantemps:
	@rm -f $(notdir $(SRC_FILES:.vala=.c)) $(notdir $(SRC_FILES:.vala=.o))
	@rm -f .stamp

.PHONY: clean
clean: cleantemps
	@rm -f $(PLUGIN).so $(OFILES) $(CFILES)

.PHONY: distclean
distclean: clean

.PHONY: listfiles
listfiles:
	@printf "plugins/$(PLUGIN)/Makefile $(foreach file,$(SRC_FILES),plugins/$(PLUGIN)/$(file)) "

