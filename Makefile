CC ?= gcc
AR ?= ar

CFLAGS ?= -O2 -g -Wall -Wextra -Wshadow -Wconversion -Wno-sign-conversion -std=c11
CPPFLAGS ?= -Iinclude
LDFLAGS ?=

# Linux-only assumptions (per project constraints)
LDLIBS_COMMON = -pthread

BIN_DIR := bin
BUILD_DIR := build
LIB_DIR := lib

LIBPROTO_A := $(LIB_DIR)/libproto.a
LIBNET_A   := $(LIB_DIR)/libnet.a
LIBLOG_A   := $(LIB_DIR)/liblog.a

SERVER_BIN := $(BIN_DIR)/server
CLIENT_BIN := $(BIN_DIR)/client

COMMON_OBJS := \
	$(BUILD_DIR)/common/log.o \
	$(BUILD_DIR)/common/net.o \
	$(BUILD_DIR)/common/proto.o

SERVER_OBJS := \
	$(BUILD_DIR)/server/main.o \
	$(BUILD_DIR)/server/shm_state.o \
	$(BUILD_DIR)/server/worker.o

CLIENT_OBJS := \
	$(BUILD_DIR)/client/main.o \
	$(BUILD_DIR)/client/stats.o

.PHONY: all clean

all: $(SERVER_BIN) $(CLIENT_BIN)

$(BIN_DIR) $(BUILD_DIR) $(LIB_DIR):
	mkdir -p $@

$(BUILD_DIR)/common $(BUILD_DIR)/server $(BUILD_DIR)/client: | $(BUILD_DIR)
	mkdir -p $@

$(BUILD_DIR)/common/%.o: src/common/%.c | $(BUILD_DIR)/common
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/server/%.o: src/server/%.c | $(BUILD_DIR)/server
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/client/%.o: src/client/%.c | $(BUILD_DIR)/client
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(LIBPROTO_A): $(BUILD_DIR)/common/proto.o | $(LIB_DIR)
	$(AR) rcs $@ $^

$(LIBNET_A): $(BUILD_DIR)/common/net.o | $(LIB_DIR)
	$(AR) rcs $@ $^

$(LIBLOG_A): $(BUILD_DIR)/common/log.o | $(LIB_DIR)
	$(AR) rcs $@ $^

$(SERVER_BIN): $(SERVER_OBJS) $(LIBPROTO_A) $(LIBNET_A) $(LIBLOG_A) | $(BIN_DIR)
	$(CC) $(LDFLAGS) -o $@ $(SERVER_OBJS) $(LIBPROTO_A) $(LIBNET_A) $(LIBLOG_A) $(LDLIBS_COMMON)

$(CLIENT_BIN): $(CLIENT_OBJS) $(LIBPROTO_A) $(LIBNET_A) $(LIBLOG_A) | $(BIN_DIR)
	$(CC) $(LDFLAGS) -o $@ $(CLIENT_OBJS) $(LIBPROTO_A) $(LIBNET_A) $(LIBLOG_A) $(LDLIBS_COMMON)

clean:
	rm -rf $(BUILD_DIR) $(BIN_DIR) $(LIB_DIR)



