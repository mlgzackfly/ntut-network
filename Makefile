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
METRICS_BIN := $(BIN_DIR)/metrics
INTERACTIVE_BIN := $(BIN_DIR)/interactive

TEST_PROTO_BIN := $(BIN_DIR)/test_proto
TEST_SHM_BIN   := $(BIN_DIR)/test_shm

COMMON_OBJS := \
	$(BUILD_DIR)/common/log.o \
	$(BUILD_DIR)/common/net.o \
	$(BUILD_DIR)/common/proto.o

SERVER_OBJS := \
	$(BUILD_DIR)/server/main.o \
	$(BUILD_DIR)/server/shm_state.o \
	$(BUILD_DIR)/server/worker.o

METRICS_OBJS := \
	$(BUILD_DIR)/server/metrics.o \
	$(BUILD_DIR)/server/shm_state.o

CLIENT_OBJS := \
	$(BUILD_DIR)/client/main.o \
	$(BUILD_DIR)/client/stats.o

INTERACTIVE_OBJS := \
	$(BUILD_DIR)/client/interactive.o

TEST_PROTO_OBJ := $(BUILD_DIR)/tests/unit/test_proto.o
TEST_SHM_OBJ   := $(BUILD_DIR)/tests/unit/test_shm.o

.PHONY: all clean unit-test system-test test

all: $(SERVER_BIN) $(CLIENT_BIN) $(METRICS_BIN) $(INTERACTIVE_BIN)

$(BIN_DIR) $(BUILD_DIR) $(LIB_DIR):
	mkdir -p $@

$(BUILD_DIR)/common $(BUILD_DIR)/server $(BUILD_DIR)/client: | $(BUILD_DIR)
	mkdir -p $@

$(BUILD_DIR)/tests/unit: | $(BUILD_DIR)
	mkdir -p $@

$(BUILD_DIR)/common/%.o: src/common/%.c | $(BUILD_DIR)/common
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/server/%.o: src/server/%.c | $(BUILD_DIR)/server
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/client/%.o: src/client/%.c | $(BUILD_DIR)/client
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/tests/unit/%.o: tests/unit/%.c | $(BUILD_DIR)/tests/unit
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(LIBPROTO_A): $(BUILD_DIR)/common/proto.o | $(LIB_DIR)
	$(AR) rcs $@ $^

$(LIBNET_A): $(BUILD_DIR)/common/net.o | $(LIB_DIR)
	$(AR) rcs $@ $^

$(LIBLOG_A): $(BUILD_DIR)/common/log.o | $(LIB_DIR)
	$(AR) rcs $@ $^

$(SERVER_BIN): $(SERVER_OBJS) $(LIBPROTO_A) $(LIBNET_A) $(LIBLOG_A) | $(BIN_DIR)
	$(CC) $(LDFLAGS) -o $@ $(SERVER_OBJS) $(LIBPROTO_A) $(LIBNET_A) $(LIBLOG_A) $(LDLIBS_COMMON)

$(METRICS_BIN): $(METRICS_OBJS) $(LIBLOG_A) | $(BIN_DIR)
	$(CC) $(LDFLAGS) -o $@ $(METRICS_OBJS) $(LIBLOG_A) $(LDLIBS_COMMON)

$(CLIENT_BIN): $(CLIENT_OBJS) $(LIBPROTO_A) $(LIBNET_A) $(LIBLOG_A) | $(BIN_DIR)
	$(CC) $(LDFLAGS) -o $@ $(CLIENT_OBJS) $(LIBPROTO_A) $(LIBNET_A) $(LIBLOG_A) $(LDLIBS_COMMON)

$(INTERACTIVE_BIN): $(INTERACTIVE_OBJS) $(LIBPROTO_A) $(LIBNET_A) $(LIBLOG_A) | $(BIN_DIR)
	$(CC) $(LDFLAGS) -o $@ $(INTERACTIVE_OBJS) $(LIBPROTO_A) $(LIBNET_A) $(LIBLOG_A) $(LDLIBS_COMMON)

$(TEST_PROTO_BIN): $(TEST_PROTO_OBJ) $(LIBPROTO_A) $(LIBLOG_A) | $(BIN_DIR)
	$(CC) $(LDFLAGS) -o $@ $(TEST_PROTO_OBJ) $(LIBPROTO_A) $(LIBLOG_A) $(LDLIBS_COMMON)

$(TEST_SHM_BIN): $(TEST_SHM_OBJ) $(BUILD_DIR)/server/shm_state.o $(LIBPROTO_A) $(LIBLOG_A) | $(BIN_DIR)
	$(CC) $(LDFLAGS) -o $@ $(TEST_SHM_OBJ) $(BUILD_DIR)/server/shm_state.o $(LIBPROTO_A) $(LIBLOG_A) $(LDLIBS_COMMON)

unit-test: $(TEST_PROTO_BIN) $(TEST_SHM_BIN)
	$(TEST_PROTO_BIN)
	$(TEST_SHM_BIN)

system-test: all
	bash scripts/test_system.sh

test: unit-test system-test

# Code quality checks
check-memory:
	@echo "Running memory leak detection..."
	@bash scripts/check_memory.sh

check-static:
	@echo "Running static analysis..."
	@bash scripts/check_static.sh

check: check-static check-memory
	@echo "All code quality checks complete"

clean:
	rm -rf $(BUILD_DIR) $(BIN_DIR) $(LIB_DIR)

.PHONY: check-memory check-static check



