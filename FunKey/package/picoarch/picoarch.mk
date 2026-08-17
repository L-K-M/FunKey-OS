################################################################################
#
# picoarch
#
################################################################################

PICOARCH_VERSION = HEAD
PICOARCH_SITE_METHOD = git
PICOARCH_SITE = https://github.com/DrUm78/picoarch.git
PICOARCH_LICENSE = GPL-2+, LGPL-2.1+, MAME
PICOARCH_LICENSE_FILES = LICENSE

PICOARCH_DEPENDENCIES = sdl sdl_image sdl_ttf

PICOARCH_SDL_CFLAGS += $(shell $(STAGING_DIR)/usr/bin/sdl-config --cflags)
PICOARCH_SDL_LIBS   += $(shell $(STAGING_DIR)/usr/bin/sdl-config --libs)

PICOARCH_CFLAGS += $(PICOARCH_SDL_CFLAGS)
PICOARCH_CFLAGS += -DFUNKEY_S -Ofast -DNDEBUG  -D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64
PICOARCH_CFLAGS += -Wall -fdata-sections -ffunction-sections -flto
PICOARCH_CFLAGS += -I./ -I./libretro-common/include/

PICOARCH_GIT_REVISION ?= $(shell cut -c1-7 "$(@D)/../../../../download/picoarch/git/.git/FETCH_HEAD")
PICOARCH_CFLAGS += -DREVISION=\"$(PICOARCH_GIT_REVISION)\"

PICOARCH_LIBS += $(PICOARCH_SDL_LIBS)
PICOARCH_LIBS += -lc -ldl -lgcc -lm -lSDL -lasound -lpng -lz -Wl,--gc-sections -flto -lSDL_image -lSDL_ttf

# The emulator cores. Every launcher in the rootfs overlay runs picoarch
# against one of these by absolute path -- gb_launch.sh is
#
#     picoarch /usr/games/gambatte_libretro.so "$1"
#
# and there are thirteen more like it. Nothing in this tree built or installed
# them, so every image ever produced from this repository has shipped without
# a single core: picoarch starts, cannot load the core, and exits, which on
# the console is a black screen and an immediate return to the launcher. The
# files were never in the repository either -- *.so has been in .gitignore
# since before the fork -- so the official images must have been built where
# they happened to exist on disk.
#
# picoarch's own Makefile knows how to build them ("cores: $(SOFILES)"), but
# its CORES list is 29: everything it supports. Build the fourteen the
# launchers here actually name. The other fifteen are emulators nothing on
# this image can reach, and each one is a clone and a cross-compile.
PICOARCH_CORES = \
	fake-08 \
	fbalpha2012 \
	fceumm \
	gambatte \
	gpsp \
	mame2000 \
	mednafen_lynx \
	mednafen_ngp \
	mednafen_pce_fast \
	mednafen_wswan \
	pcsx_rearmed \
	picodrive \
	pokemini \
	snes9x2005

# picoarch carries two patches per core: 1000-trimui-build.patch, which adds a
# trimui branch to the core's own Makefile, and an optional 0001-* tweak
# against the core's libretro.cpp. funkey-s builds cores as
# unix-armv7-hardfloat-neon, so the trimui ones are inert here and matter only
# in that they apply.
#
# The 0001-* tweaks are where upstream drift lands, because they touch code
# that changes. Two of them no longer apply: gambatte's adds an extra LCD
# ghosting mode, mednafen_pce_fast's adds a frameskip interval, and each fails
# a hunk against its upstream's current master. picoarch clones cores
# unpinned, so this is not a state anything here chose and not one that will
# stay fixed by itself.
#
# Drop those two rather than pin the cores to whatever commit last accepted
# them. What is lost is one optional quality knob in each of two emulators;
# what pinning would cost is freezing two cores at an old commit, missing
# every upstream fix since, to keep them. Both patches are worth restoring if
# they turn out to matter on this hardware -- they are performance options and
# this is slow hardware -- but rebased rather than pinned to.
define PICOARCH_DROP_STALE_CORE_PATCHES
	rm -f $(@D)/patches/gambatte/0001-ghosting-fastest.patch
	rm -f $(@D)/patches/mednafen_pce_fast/0001-frameskip-interval.patch
endef
PICOARCH_POST_EXTRACT_HOOKS += PICOARCH_DROP_STALE_CORE_PATCHES

define PICOARCH_BUILD_CMDS
	(cd $(@D); \
	make picoarch platform=funkey-s \
	CROSS_COMPILE=$(TARGET_CROSS) \
	CFLAGS='$(PICOARCH_CFLAGS)' \
	LDFLAGS='$(PICOARCH_LIBS)' \
	SDL_INCLUDES='$(PICOARCH_SDL_CFLAGS)' \
	SDL_LIBS='$(PICOARCH_SDL_LIBS)' \
	)
	# Deliberately without CFLAGS/LDFLAGS: those are picoarch's own, they name
	# SDL, and a variable set on the command line reaches every sub-make --
	# which here means every core's build, each of which sets its own.
	#
	# CXX has to be given even though CROSS_COMPILE is: make has a built-in
	# CXX = g++, the core Makefiles only set it with ?=, and a built-in
	# counts as defined. Without it the C sources compile for ARM, the C++
	# sources compile for the host, and the link fails on "file in wrong
	# format" after everything has already been built.
	#
	# The parallelism goes here, on the cores as a whole, and PROCS= takes it
	# back out of each core's own build -- picoarch passes every core's make
	# a -j4 of its own. That is not a tuning preference.
	#
	# Several cores link with -flto, and gcc's lto-wrapper parallelises an
	# LTO link by writing a makefile and running make on it -- but only when
	# it finds a job server advertised in MAKEFLAGS. A make handed -j on its
	# own command line resets job server mode: it creates one, advertises it
	# to everything it runs, and closes the pipe for every recipe line that
	# is not itself a make. A link is such a line, so lto-wrapper's make
	# inherits a job server that is not there and dies on it:
	#
	#     make: *** write jobserver: Bad file descriptor.  Stop.
	#     lto-wrapper: fatal error: make returned 2 exit status
	#     ld: error: lto-wrapper failed
	#
	# picodrive fails exactly this way, every time. A make with no -j of its
	# own does not republish the stale advertisement it inherited, it strips
	# it -- which leaves lto-wrapper nothing to find and the LTO link runs in
	# one process. So build four cores at once rather than four files of one
	# core at once: the same jobs, and the level that breaks is gone.
	(cd $(@D); \
	make cores -j$(PARALLEL_JOBS) platform=funkey-s \
	CORES='$(PICOARCH_CORES)' \
	PROCS= \
	CROSS_COMPILE=$(TARGET_CROSS) \
	CC=$(TARGET_CROSS)gcc \
	CXX=$(TARGET_CROSS)g++ \
	)
endef

PICOARCH_GIT_SUBMODULES = YES

define PICOARCH_INSTALL_TARGET_CMDS
	$(INSTALL) -d -m 0755 $(TARGET_DIR)/usr/games
	$(INSTALL) -m 0755 $(@D)/picoarch $(TARGET_DIR)/usr/games/
	# Named rather than globbed, so a core that failed to build fails the
	# install too instead of quietly leaving one system dead on the console.
	#
	# fake-08 is renamed on the way in: picoarch names the built file after
	# the core, and the core is called fake-08, but pico8_launch.sh runs
	# /usr/games/fake08_libretro.so.
	for core in $(PICOARCH_CORES); do \
		dst="$${core}_libretro.so"; \
		if [ "$${core}" = fake-08 ]; then dst=fake08_libretro.so; fi; \
		$(INSTALL) -m 0755 "$(@D)/$${core}_libretro.so" \
			"$(TARGET_DIR)/usr/games/$${dst}" || exit 1; \
	done
endef

define PICOARCH_CREATE_OPK
	$(INSTALL) -d -m 0755 $(TARGET_DIR)/usr/local/share/OPKs/Libretro
	$(HOST_DIR)/usr/bin/mksquashfs $(PICOARCH_PKGDIR)/opk/picoarch $(TARGET_DIR)/usr/local/share/OPKs/Libretro/picoarch_funkey-s.opk -all-root -noappend -no-exports -no-xattrs
	$(HOST_DIR)/usr/bin/mksquashfs $(PICOARCH_PKGDIR)/opk/gb_gbc $(TARGET_DIR)/usr/local/share/OPKs/Libretro/gb_gbc_picoarch_funkey-s.opk -all-root -noappend -no-exports -no-xattrs
	$(HOST_DIR)/usr/bin/mksquashfs $(PICOARCH_PKGDIR)/opk/gba $(TARGET_DIR)/usr/local/share/OPKs/Libretro/gba_picoarch_funkey-s.opk -all-root -noappend -no-exports -no-xattrs
	$(HOST_DIR)/usr/bin/mksquashfs $(PICOARCH_PKGDIR)/opk/lynx $(TARGET_DIR)/usr/local/share/OPKs/Libretro/lynx_picoarch_funkey-s.opk -all-root -noappend -no-exports -no-xattrs
	$(HOST_DIR)/usr/bin/mksquashfs $(PICOARCH_PKGDIR)/opk/megadrive $(TARGET_DIR)/usr/local/share/OPKs/Libretro/megadrive_picoarch_funkey-s.opk -all-root -noappend -no-exports -no-xattrs
	$(HOST_DIR)/usr/bin/mksquashfs $(PICOARCH_PKGDIR)/opk/nes $(TARGET_DIR)/usr/local/share/OPKs/Libretro/nes_picoarch_funkey-s.opk -all-root -noappend -no-exports -no-xattrs
	$(HOST_DIR)/usr/bin/mksquashfs $(PICOARCH_PKGDIR)/opk/ngp $(TARGET_DIR)/usr/local/share/OPKs/Libretro/ngp_picoarch_funkey-s.opk -all-root -noappend -no-exports -no-xattrs
	$(HOST_DIR)/usr/bin/mksquashfs $(PICOARCH_PKGDIR)/opk/pce $(TARGET_DIR)/usr/local/share/OPKs/Libretro/pce_picoarch_funkey-s.opk -all-root -noappend -no-exports -no-xattrs
	$(HOST_DIR)/usr/bin/mksquashfs $(PICOARCH_PKGDIR)/opk/ps1 $(TARGET_DIR)/usr/local/share/OPKs/Libretro/ps1_picoarch_funkey-s.opk -all-root -noappend -no-exports -no-xattrs
	$(HOST_DIR)/usr/bin/mksquashfs $(PICOARCH_PKGDIR)/opk/snes $(TARGET_DIR)/usr/local/share/OPKs/Libretro/snes_picoarch_funkey-s.opk -all-root -noappend -no-exports -no-xattrs
	$(HOST_DIR)/usr/bin/mksquashfs $(PICOARCH_PKGDIR)/opk/wonderswan $(TARGET_DIR)/usr/local/share/OPKs/Libretro/wonderswan_picoarch_funkey-s.opk -all-root -noappend -no-exports -no-xattrs
	$(HOST_DIR)/usr/bin/mksquashfs $(PICOARCH_PKGDIR)/opk/fba2012 $(TARGET_DIR)/usr/local/share/OPKs/Libretro/fba2012_picoarch_funkey-s.opk -all-root -noappend -no-exports -no-xattrs
	$(HOST_DIR)/usr/bin/mksquashfs $(PICOARCH_PKGDIR)/opk/mame2000 $(TARGET_DIR)/usr/local/share/OPKs/Libretro/mame2000_picoarch_funkey-s.opk -all-root -noappend -no-exports -no-xattrs
	$(HOST_DIR)/usr/bin/mksquashfs $(PICOARCH_PKGDIR)/opk/pico8 $(TARGET_DIR)/usr/local/share/OPKs/Libretro/pico8_picoarch_funkey-s.opk -all-root -noappend -no-exports -no-xattrs
	$(HOST_DIR)/usr/bin/mksquashfs $(PICOARCH_PKGDIR)/opk/pokemini $(TARGET_DIR)/usr/local/share/OPKs/Libretro/pokemini_picoarch_funkey-s.opk -all-root -noappend -no-exports -no-xattrs
	$(HOST_DIR)/usr/bin/mksquashfs $(PICOARCH_PKGDIR)/opk/prboom $(TARGET_DIR)/usr/local/share/OPKs/Libretro/prboom_picoarch_funkey-s.opk -all-root -noappend -no-exports -no-xattrs
	$(HOST_DIR)/usr/bin/mksquashfs $(PICOARCH_PKGDIR)/opk/tyrquake $(TARGET_DIR)/usr/local/share/OPKs/Libretro/tyrquake_picoarch_funkey-s.opk -all-root -noappend -no-exports -no-xattrs
	$(HOST_DIR)/usr/bin/mksquashfs $(PICOARCH_PKGDIR)/opk/vitaquake2 $(TARGET_DIR)/usr/local/share/OPKs/Libretro/vitaquake2_picoarch_funkey-s.opk -all-root -noappend -no-exports -no-xattrs
	$(HOST_DIR)/usr/bin/mksquashfs $(PICOARCH_PKGDIR)/opk/ecwolf $(TARGET_DIR)/usr/local/share/OPKs/Libretro/ecwolf_picoarch_funkey-s.opk -all-root -noappend -no-exports -no-xattrs
endef
PICOARCH_POST_INSTALL_TARGET_HOOKS += PICOARCH_CREATE_OPK

$(eval $(generic-package))
