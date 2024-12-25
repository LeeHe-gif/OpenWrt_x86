--- a/include/image.mk
+++ b/include/image.mk
@@ -717,7 +717,7 @@
 endef
 
 define Device/Build/image
-  GZ_SUFFIX := $(if $(filter %dtb %gz,$(2)),,$(if $(and $(findstring ext4,$(1)),$(CONFIG_TARGET_IMAGES_GZIP)),.gz))
+  GZ_SUFFIX := $(if $(filter %dtb %gz,$(2)),,$(if $(and $(findstring ext4,$(1)),$(findstring img,$(2)),$(CONFIG_TARGET_IMAGES_GZIP)),.gz))
   $$(_TARGET): $(if $(CONFIG_JSON_OVERVIEW_IMAGE_INFO), \
 	  $(BUILD_DIR)/json_info_files/$(call DEVICE_IMG_NAME,$(1),$(2)).json, \
 	  $(BIN_DIR)/$(call DEVICE_IMG_NAME,$(1),$(2))$$(GZ_SUFFIX))
@@ -861,6 +861,7 @@
 Target-Profile: DEVICE_$(1)
 Target-Profile-Name: $(DEVICE_DISPLAY)
 Target-Profile-Packages: $(DEVICE_PACKAGES)
+Target-Profile-ImageSize: $(shell echo $$(( $(call exp_units,$(IMAGE_SIZE)) / 1024 )))
 Target-Profile-hasImageMetadata: $(if $(foreach image,$(IMAGES),$(findstring append-metadata,$(IMAGE/$(image)))),1,0)
 Target-Profile-SupportedDevices: $(SUPPORTED_DEVICES)
 $(if $(BROKEN),Target-Profile-Broken: $(BROKEN))

--- a/scripts/target-metadata.pl
+++ b/scripts/target-metadata.pl
@@ -437,6 +437,7 @@
 		print "PROFILE_NAMES = ".join(" ", @profile_ids_unique)."\n";
 		foreach my $profile (@{$cur->{profiles}}) {
 			print $profile->{id}.'_NAME:='.$profile->{name}."\n";
+			print $profile->{id}.'_IMAGE_SIZE:='.$profile->{image_size}."\n";
 			print $profile->{id}.'_HAS_IMAGE_METADATA:='.$profile->{has_image_metadata}."\n";
 			if (defined($profile->{supported_devices}) and @{$profile->{supported_devices}} > 0) {
 				print $profile->{id}.'_SUPPORTED_DEVICES:='.join(' ', @{$profile->{supported_devices}})."\n";

--- a/scripts/metadata.pm
+++ b/scripts/metadata.pm
@@ -150,6 +150,7 @@ sub parse_target_metadata($) {
 			push @{$target->{profiles}}, $profile;
 		};
 		/^Target-Profile-Name:\s*(.+)\s*$/ and $profile->{name} = $1;
+		/^Target-Profile-ImageSize:\s*(.*)\s*/ and $profile->{image_size} = $1;
 		/^Target-Profile-hasImageMetadata:\s*(\d+)\s*$/ and $profile->{has_image_metadata} = $1;
 		/^Target-Profile-SupportedDevices:\s*(.+)\s*$/ and $profile->{supported_devices} = [ split(/\s+/, $1) ];
 		/^Target-Profile-Priority:\s*(\d+)\s*$/ and do {

--- a/target/imagebuilder/Makefile
+++ b/target/imagebuilder/Makefile
@@ -39,7 +39,8 @@
 		./files/Makefile \
 		$(TMP_DIR)/.targetinfo \
 		$(TMP_DIR)/.packageinfo \
-		$(PKG_BUILD_DIR)/
+		$(TOPDIR)/files \
+		$(PKG_BUILD_DIR)/ || true
 
 	$(INSTALL_DIR) $(PKG_BUILD_DIR)/packages
 
@@ -52,12 +53,12 @@
 
 	$(INSTALL_DATA) ./files/README.apk.md $(PKG_BUILD_DIR)/packages/README.md
 else
-  ifeq ($(CONFIG_IB_STANDALONE),)
 	echo '## Remote package repositories' >> $(PKG_BUILD_DIR)/repositories.conf
 	$(call FeedSourcesAppendOPKG,$(PKG_BUILD_DIR)/repositories.conf)
 	$(VERSION_SED_SCRIPT) $(PKG_BUILD_DIR)/repositories.conf
-
-  endif
+	$(SED) 's/^src\/gz \(.*\) https.*ai\/\(.*packages.*\)/src \1 file:\/\/www\/wwwroot\/op.miaogongzi.cc\/\2/' $(PKG_BUILD_DIR)/repositories.conf
+	$(SED) 's/^src\/gz \(.*\) https.*ai\/\(.*targets.*\)/src \1 file:\/\/www\/wwwroot\/op.miaogongzi.cc\/\2/' $(PKG_BUILD_DIR)/repositories.conf
+	$(SED) '/openwrt_core/d' $(PKG_BUILD_DIR)/repositories.conf
 
 	# create an empty package index so `opkg` doesn't report an error
 	touch $(PKG_BUILD_DIR)/packages/Packages


--- a/target/imagebuilder/files/Makefile
+++ b/target/imagebuilder/files/Makefile
@@ -142,6 +142,36 @@
 # "-pkgname" in the package list means remove "pkgname" from the package list
 BUILD_PACKAGES:=$(filter-out $(filter -%,$(BUILD_PACKAGES)) $(patsubst -%,%,$(filter -%,$(BUILD_PACKAGES))),$(BUILD_PACKAGES))
 BUILD_PACKAGES:=$(USER_PACKAGES) $(BUILD_PACKAGES)
+IMAGE_SIZE_VALUE := $($(USER_PROFILE)_IMAGE_SIZE)
+ifdef IMAGE_SIZE_VALUE
+	ifeq ($(shell test $(IMAGE_SIZE_VALUE) -le 35840 && echo true),true)
+		SMALL_FLASH := true
+	endif
+	ifeq ($(shell test $(IMAGE_SIZE_VALUE) -le 20480 && echo true),true)
+		XSMALL_FLASH := true
+	endif
+endif
+ifneq ($(findstring usb,$(BUILD_PACKAGES)),)
+	ifneq ($(XSMALL_FLASH),true)
+		BUILD_PACKAGES += automount luci-app-diskman
+	endif
+endif
+ifeq ($(SMALL_FLASH),true)
+	ifeq ($(XSMALL_FLASH),true)
+		BUILD_PACKAGES += -coremark -htop -bash -openssh-sftp-server
+	endif
+	ifeq ($(shell grep -q small_flash $(TOPDIR)/repositories.conf || echo "not_found"),not_found)
+        $(shell echo "`grep MeowWrt_miaogongzi $(TOPDIR)/repositories.conf | sed -e 's/miaogongzi/small_flash/g'`" >>$(TOPDIR)/repositories.conf)
+	endif
+	ifneq ($(findstring /data/bcache/,$(BIN_DIR)),)
+		BUILD_PACKAGES += -luci-app-homeproxy -luci-app-istorex -luci-theme-argon
+	endif
+else
+        $(shell sed -i "/small_flash/d" $(TOPDIR)/repositories.conf)
+endif
+define add_zh_cn_packages
+$(eval BUILD_PACKAGES += $(foreach pkg,$(BUILD_PACKAGES),$(if $(and $(filter luci-app-%,$(pkg)),$(shell $(OPKG) list | grep -q "^luci-i18n-$(patsubst luci-app-%,%,$(pkg))-zh-cn" && echo 1)),luci-i18n-$(patsubst luci-app-%,%,$(pkg))-zh-cn)))
+endef
 BUILD_PACKAGES:=$(filter-out $(filter -%,$(BUILD_PACKAGES)) $(patsubst -%,%,$(filter -%,$(BUILD_PACKAGES))),$(BUILD_PACKAGES))
 PACKAGES:=
 
@@ -157,6 +187,8 @@
 	$(MAKE) -s build_image
 	$(MAKE) -s json_overview_image_info
 	$(MAKE) -s checksum
+	rm -rf $(KERNEL_BUILD_DIR)/tmp
+	rm -rf $(KERNEL_BUILD_DIR)/root.*
 
 _call_manifest: FORCE
 	rm -rf $(TARGET_DIR)
@@ -224,9 +256,17 @@
 	@echo
 	@echo Installing packages...
 ifeq ($(CONFIG_USE_APK),)
+    $(eval $(call add_zh_cn_packages))
 	$(OPKG) install $(firstword $(wildcard $(LINUX_DIR)/libc_*.ipk $(PACKAGE_DIR)/libc_*.ipk))
 	$(OPKG) install $(firstword $(wildcard $(LINUX_DIR)/kernel_*.ipk $(PACKAGE_DIR)/kernel_*.ipk))
-	$(OPKG) install $(BUILD_PACKAGES)
+	$(OPKG) install --force-maintainer $(BUILD_PACKAGES) luci-i18n-base-zh-cn || true
+	$(if $(USER_FILES), \
+	find $(USER_FILES) -name "*.ipk" -print0 | \
+	while IFS= read -r -d '' ipk; do \
+		$(OPKG) install "$$ipk" && rm -f "$$ipk" || true; \
+	done; \
+	)
+	$(OPKG) install --force-maintainer --force-reinstall my-default-settings 2>/dev/null
 else
 	$(APK) add --no-scripts $(firstword $(wildcard $(LINUX_DIR)/libc-*.apk $(PACKAGE_DIR)/libc-*.apk))
 	$(APK) add --no-scripts $(firstword $(wildcard $(LINUX_DIR)/kernel-*.apk $(PACKAGE_DIR)/kernel-*.apk))
@@ -237,7 +277,7 @@
 	@echo
 	@echo Finalizing root filesystem...
 
-	$(CP) $(TARGET_DIR) $(TARGET_DIR_ORIG)
+	mkdir -p "$(TARGET_DIR_ORIG)" && (tar -C "$(TARGET_DIR)" -cf - .) | pv -trab --buffer-size 100M | (tar -C "$(TARGET_DIR_ORIG)" -xf - .)
 ifeq ($(CONFIG_USE_APK),)
 	$(if $(CONFIG_SIGNATURE_CHECK), \
 		$(if $(ADD_LOCAL_KEY), \
@@ -254,6 +294,9 @@
 	)
 endif
 	$(call prepare_rootfs,$(TARGET_DIR),$(USER_FILES),$(DISABLED_SERVICES))
+	$(if $(SMALL_FLASH), \
+        $(shell echo "`grep MeowWrt_miaogongzi $(TOPDIR)/repositories.conf | sed -e 's/miaogongzi/small_flash/g'`" >>$(BUILD_DIR)/root-*/etc/opkg/distfeeds.conf) \
+	)
 
 build_image: FORCE
 	@echo
