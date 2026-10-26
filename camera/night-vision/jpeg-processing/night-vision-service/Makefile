APP_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SHELL := /bin/bash
export LC_ALL := C

RKIPC_NIGHT_MODE ?= 1
BUILD_DIR ?= $(APP_DIR)/build/$(RKIPC_NIGHT_MODE)
OBJECT := $(BUILD_DIR)/night-vision.o
RKIPC_ISP_OBJECT := $(BUILD_DIR)/rkipc_isp.o
CXXFLAGS ?= -std=c++11 -O2 -Wall -Wextra

ifeq ($(RKIPC_NIGHT_MODE),0)
else ifeq ($(RKIPC_NIGHT_MODE),1)
else
$(error RKIPC_NIGHT_MODE must be 0 or 1)
endif
CXXFLAGS += -DRKIPC_NIGHT_MODE=$(RKIPC_NIGHT_MODE)

.PHONY: all clean print-config FORCE

ifneq ($(wildcard $(APP_DIR)/../Makefile.param),)
# Staged under project/app: use the selected Rockchip cross compiler and
# package the executable into the firmware root filesystem.
include $(APP_DIR)/../Makefile.param
CROSS_COMPILE ?= $(RK_APP_CROSS)-
PKG_BIN ?= $(APP_DIR)/out
TARGET := $(PKG_BIN)/root/usr/bin/night-vision
SDK_PACKAGE := yes
else
# Standalone build with the SDK ARM/uClibc toolchain.
REPO_ROOT := $(abspath $(APP_DIR)/../../../..)
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

$(OBJECT): $(APP_DIR)/night-vision.cpp $(APP_DIR)/rkipc_isp.h | $(BUILD_DIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c $< -o $@

$(RKIPC_ISP_OBJECT): $(APP_DIR)/rkipc_isp.cpp $(APP_DIR)/rkipc_isp.h | $(BUILD_DIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c $< -o $@

$(TARGET): $(OBJECT) $(RKIPC_ISP_OBJECT) FORCE | $(dir $(TARGET))
	$(CXX) $(LDFLAGS) $(OBJECT) $(RKIPC_ISP_OBJECT) $(LDLIBS) -o $@

FORCE:

print-config:
	@printf 'SDK_PACKAGE=%s\nRKIPC_NIGHT_MODE=%s\nCROSS_COMPILE=%s\nTARGET=%s\n' \
		'$(SDK_PACKAGE)' '$(RKIPC_NIGHT_MODE)' '$(CROSS_COMPILE)' '$(TARGET)'
	@if [ "$(SDK_PACKAGE)" = no ]; then \
		printf 'SDK_ROOT=%s\nTOOLCHAIN_DIR=%s\n' '$(SDK_ROOT)' '$(TOOLCHAIN_DIR)'; \
	fi

clean:
	rm -f $(TARGET) $(OBJECT) $(RKIPC_ISP_OBJECT)
