################################################################################
#
# fonts-droid
#
################################################################################

FONTS_DROID_VERSION = 074990596701553b8b51ff22290453de522f0d15
FONTS_DROID_SITE = https://android.googlesource.com/platform/frameworks/base/+archive/$(FONTS_DROID_VERSION)/data
FONTS_DROID_SOURCE = fonts.tar.gz
FONTS_DROID_LICENSE = Apache-2.0

FONTS_DROID_STRIP_COMPONENTS = 0

# We cannot verify the hash because googlesource.com produces an archive
# with a different hash on every request.
#
# This still issues a warning.
BR_NO_CHECK_HASH_FOR += $(FONTS_DROID_SOURCE)

# truetype/droid, not droid. Nothing on the image asks for these fonts by any
# other name, and the only thing that asks for them at all looks here:
#
#     gmenu2x/src/gmenu2x.cpp
#     #define DEFAULT_FALLBACK_FONTS \
#       ,{"/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf",13}, \
#        {"/usr/share/fonts/truetype/droid/DroidSansFallback.ttf",13}
#
# That is the fallback stack gmenu2x consults for a glyph its skin font does
# not have, which is every glyph outside Latin -- so it is what draws Chinese,
# Japanese, Korean and Cyrillic in the launcher. Installed one directory up
# from where it is looked for, it was never opened: gmenu2x already offers
# 简体中文 among its languages and already ships the translation, and choosing
# it produced a screen of empty boxes. This is also the path Debian and Android
# use, so it is the one anything else added later will expect.
define FONTS_DROID_INSTALL_TARGET_CMDS
	mkdir -p $(TARGET_DIR)/usr/share/fonts/truetype/droid/
	install -m 0644 $(@D)/NOTICE $(@D)/DroidSansFallback.ttf \
	  $(TARGET_DIR)/usr/share/fonts/truetype/droid/
	install -m 0644 $(@D)/NOTICE $(@D)/DroidSansFallbackFull.ttf \
	  $(TARGET_DIR)/usr/share/fonts/truetype/droid/
endef

$(eval $(generic-package))
