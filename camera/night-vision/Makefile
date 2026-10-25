APP_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SHELL := /bin/bash
export LC_ALL := C

BUILD_DIR ?= $(APP_DIR)/build
OBJECT := $(BUILD_DIR)/night-vision.o
CXXFLAGS ?= -std=c++11 -O2 -Wall -Wextra

.PHONY: all clean print-config

ifneq ($(wildcard $(APP_DIR)/../Makefile.param),)
# When staged under project/app, use the SDK-selected cross compiler and stage
# the executable for inclusion in the firmware root filesystem.
include $(APP_DIR)/../Makefile.param
CROSS_COMPILE ?= $(RK_APP_CROSS)-
PKG_BIN ?= $(APP_DIR)/out
TARGET := $(PKG_BIN)/root/usr/bin/night-vision
SDK_PACKAGE := yes
else
# Standalone build using the SDK's ARM/uClibc toolchain.
REPO_ROOT := $(abspath $(APP_DIR)/../..)
SDK_ROOT ?= $(REPO_ROOT)/sdk/luckfox-pico
TOOLCHAIN_DIR ?= $(SDK_ROOT)/tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf/bin
CROSS_COMPILE ?= $(TOOLCHAIN_DIR)/arm-rockchip830-linux-uclibcgnueabihf-
TARGET := $(BUILD_DIR)/night-vision
SDK_PACKAGE := no
endif

CXX = $(CROSS_COMPILE)g++

ifeq ($(SDK_PACKAGE),yes)
all: $(TARGET)
	$(call MAROC_COPY_PKG_TO_APP_OUTPUT, $(RK_APP_OUTPUT), $(PKG_BIN))
else
all: $(TARGET)
endif

$(BUILD_DIR) $(dir $(TARGET)):
	mkdir -p $@

$(OBJECT): $(APP_DIR)/night-vision.cpp | $(BUILD_DIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c $< -o $@

$(TARGET): $(OBJECT) | $(dir $(TARGET))
	$(CXX) $(LDFLAGS) $^ $(LDLIBS) -o $@

print-config:
	@printf 'SDK_PACKAGE=%s\nCROSS_COMPILE=%s\nTARGET=%s\n' \
		'$(SDK_PACKAGE)' '$(CROSS_COMPILE)' '$(TARGET)'
	@if [ "$(SDK_PACKAGE)" = no ]; then \
		printf 'SDK_ROOT=%s\nTOOLCHAIN_DIR=%s\n' '$(SDK_ROOT)' '$(TOOLCHAIN_DIR)'; \
	fi

clean:
	rm -f $(TARGET) $(OBJECT)
