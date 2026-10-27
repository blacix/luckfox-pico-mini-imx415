APP_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SHELL := /bin/bash
export LC_ALL := C
BUILD_DIR ?= $(APP_DIR)/build
MAIN_OBJECT := $(BUILD_DIR)/main.o
TJPGD_OBJECT := $(BUILD_DIR)/tjpgd.o

TJPGD_DIR := $(APP_DIR)/tjpgd3/src

CFLAGS ?= -std=c99 -O2 -Wall -Wextra
CXXFLAGS ?= -std=c++11 -O2 -Wall -Wextra
LDLIBS += -pthread

.PHONY: all clean print-config

ifneq ($(wildcard $(APP_DIR)/../Makefile.param),)
# When staged under project/app, use the SDK's selected cross compiler and
# install the app into the rootfs staging tree consumed by build.sh.
include $(APP_DIR)/../Makefile.param
CROSS_COMPILE ?= $(RK_APP_CROSS)-
COMMON_DIR := $(APP_DIR)/common
PKG_BIN ?= $(APP_DIR)/out
TARGET := $(PKG_BIN)/root/usr/bin/night-vision-measurement
SDK_PACKAGE := yes
else
# Standalone development build using the SDK compiler directly.
REPO_ROOT := $(abspath $(APP_DIR)/../../../..)
SDK_ROOT ?= $(REPO_ROOT)/sdk/luckfox-pico
TOOLCHAIN_DIR ?= $(SDK_ROOT)/tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf/bin
CROSS_COMPILE ?= $(TOOLCHAIN_DIR)/arm-rockchip830-linux-uclibcgnueabihf-
COMMON_DIR := $(APP_DIR)/../../common
TARGET := $(BUILD_DIR)/night-vision-measurement
SDK_PACKAGE := no
endif

CC = $(CROSS_COMPILE)gcc
CXX = $(CROSS_COMPILE)g++
CPPFLAGS += -I$(TJPGD_DIR) -I$(COMMON_DIR)

ifeq ($(SDK_PACKAGE),yes)
all: $(TARGET)
	$(call MAROC_COPY_PKG_TO_APP_OUTPUT, $(RK_APP_OUTPUT), $(PKG_BIN))
else
all: $(TARGET)
endif

$(BUILD_DIR) $(dir $(TARGET)):
	mkdir -p $@

$(MAIN_OBJECT): $(APP_DIR)/main.cpp $(COMMON_DIR)/brightness_metrics.h | $(BUILD_DIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c $< -o $@

$(TJPGD_OBJECT): $(TJPGD_DIR)/tjpgd.c $(TJPGD_DIR)/tjpgd.h $(TJPGD_DIR)/tjpgdcnf.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(TARGET): $(MAIN_OBJECT) $(TJPGD_OBJECT) | $(dir $(TARGET))
	$(CXX) $(LDFLAGS) $^ $(LDLIBS) -o $@

print-config:
	@printf 'SDK_PACKAGE=%s\nCROSS_COMPILE=%s\nTARGET=%s\n' \
		'$(SDK_PACKAGE)' '$(CROSS_COMPILE)' '$(TARGET)'
	@if [ "$(SDK_PACKAGE)" = no ]; then \
		printf 'SDK_ROOT=%s\nTOOLCHAIN_DIR=%s\n' '$(SDK_ROOT)' '$(TOOLCHAIN_DIR)'; \
	fi

clean:
	rm -f $(TARGET) $(BUILD_DIR)/night-vision-jpeg $(MAIN_OBJECT) $(TJPGD_OBJECT)
