################################################################################
#
# gmu
#
################################################################################

GMU_VERSION = HEAD
GMU_SITE_METHOD = git
GMU_SITE = https://github.com/DrUm78/gmu.git
GMU_LICENSE = GPL-2.0
GMU_LICENSE_FILES = LICENSE

GMU_DEPENDENCIES = sdl

# funkey.mk in the gmu sources hardcodes a hand-installed SDK at
# /opt/FunKey-sdk -- the compiler, and the sysroot it takes SDL and the libc
# headers from. That path does not exist in a buildroot tree, so the build died
# with
#
#   /opt/FunKey-sdk/bin/arm-funkey-linux-musleabihf-gcc: not found
#
# Rewritten to buildroot's own variables rather than to a relative path: the
# sysroot moves as well as the compiler, and it does not move in parallel --
# buildroot puts its sysroot under its own tuple, arm-buildroot-linux-musleabihf,
# while gmu asks for arm-funkey-linux-musleabihf, so substituting one prefix for
# the other would point at a directory that is not there. TARGET_CC and
# STAGING_DIR are correct whatever either tuple is called.
#
# The clock and st-sdl packages carry the same fix for the same reason; gmu is
# the one package here that never got it.
#
# TARGET_MAKE_ENV is what puts $(HOST_DIR)/bin on PATH. The package script
# cross-configures the vendored flac and wavpack with
# --host=arm-funkey-linux-musleabihf, and without that on PATH configure quietly
# fell back to the host compiler and then fed wavpack's ARM assembly to the
# x86_64 assembler, several hundred lines of "no such instruction" before the
# real error.
define GMU_BUILD_CMDS
	(cd $(@D); \
	sed -i -e 's|rm -rf|#rm -rf|g' package; \
	sed -i -e 's|make -f Makefile.funkey clean|#make -f Makefile.funkey clean|g' package; \
	sed -i -e 's|/opt/FunKey-sdk/bin/arm-funkey-linux-musleabihf-gcc|$(TARGET_CC)|g' funkey.mk; \
	sed -i -e 's|/opt/FunKey-sdk/arm-funkey-linux-musleabihf/sysroot|$(STAGING_DIR)|g' funkey.mk; \
	chmod +x package; \
	$(TARGET_MAKE_ENV) ./package \
	)
endef

define GMU_INSTALL_TARGET_CMDS
	$(INSTALL) -d -m 0755 $(TARGET_DIR)/usr/bin/gmu
	$(INSTALL) -D -m 0755 -t $(TARGET_DIR)/usr/bin/gmu $(@D)/gmu
	$(INSTALL) -D -m 0755 -t $(TARGET_DIR)/usr/bin/gmu $(@D)/opk/*
	$(INSTALL) -D -m 0755 -t $(TARGET_DIR)/usr/bin/gmu/decoders $(@D)/decoders/*
	$(INSTALL) -D -m 0755 -t $(TARGET_DIR)/usr/bin/gmu/frontends $(@D)/frontends/*
	$(INSTALL) -D -m 0755 -t $(TARGET_DIR)/usr/bin/gmu/themes/dbcompo-small $(@D)/themes/dbcompo-small/*
	$(INSTALL) -D -m 0755 -t $(TARGET_DIR)/usr/bin/gmu/themes/dbcompo-large $(@D)/themes/dbcompo-large/*
	$(INSTALL) -D -m 0755 -t $(TARGET_DIR)/usr/bin/gmu/themes/default-modern-small $(@D)/themes/default-modern-small/*
	$(INSTALL) -D -m 0755 -t $(TARGET_DIR)/usr/bin/gmu/themes/default-modern-large $(@D)/themes/default-modern-large/*
	rm -f $(TARGET_DIR)/usr/bin/gmu/gmu.funkey-s.desktop
endef

define GMU_CREATE_OPK
	$(INSTALL) -d -m 0755 $(TARGET_DIR)/usr/local/share/OPKs/Applications
	$(HOST_DIR)/usr/bin/mksquashfs $(GMU_PKGDIR)/opk $(TARGET_DIR)/usr/local/share/OPKs/Applications/gmu_funkey-s.opk -all-root -noappend -no-exports -no-xattrs
endef
GMU_POST_INSTALL_TARGET_HOOKS += GMU_CREATE_OPK

$(eval $(generic-package))
