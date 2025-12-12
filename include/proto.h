#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// Protocol constants
#define NS_MAGIC 0x4E53u /* 'N''S' */
#define NS_VERSION 1u

enum {
  NS_FLAG_ENCRYPTED = 1u << 0,
  NS_FLAG_COMPRESSED = 1u << 1,
  NS_FLAG_IS_RESPONSE = 1u << 2,
};

typedef enum {
  OP_HELLO = 0x0001,
  OP_LOGIN = 0x0002,
  OP_LOGOUT = 0x0003,
  OP_HEARTBEAT = 0x0004,

  OP_JOIN_ROOM = 0x0101,
  OP_LEAVE_ROOM = 0x0102,
  OP_CHAT_SEND = 0x0103,
  OP_CHAT_BROADCAST = 0x0104, // server push

  OP_DEPOSIT = 0x0201,
  OP_WITHDRAW = 0x0202,
  OP_TRANSFER = 0x0203,
  OP_BALANCE = 0x0204,
} opcode_t;

typedef enum {
  ST_OK = 0x0000,
  ST_ERR_BAD_PACKET = 0x0001,
  ST_ERR_CHECKSUM_FAIL = 0x0002,
  ST_ERR_UNAUTHORIZED = 0x0003,
  ST_ERR_NOT_FOUND = 0x0004,
  ST_ERR_INSUFFICIENT_FUNDS = 0x0005,
  ST_ERR_SERVER_BUSY = 0x0006,
  ST_ERR_TIMEOUT = 0x0007,
  ST_ERR_INTERNAL = 0x00ff,
} status_t;

// Fixed 32-byte header on the wire (big-endian)
// Layout:
// magic(2) version(1) flags(1) header_len(2) body_len(4) opcode(2) status(2)
// req_id(8) checksum(4) reserved(6)
typedef struct __attribute__((packed)) {
  uint16_t magic;
  uint8_t version;
  uint8_t flags;
  uint16_t header_len;
  uint32_t body_len;
  uint16_t opcode;
  uint16_t status;
  uint64_t req_id;
  uint32_t checksum;
  uint8_t reserved[6];
} ns_header_t;

// Helpers
uint32_t ns_crc32(const void *data, size_t len);
uint32_t ns_frame_checksum(const ns_header_t *hdr_be, const uint8_t *body, size_t body_len);

// Encode a header in big-endian into out_hdr (checksum is filled).
// out_hdr points to a ns_header_t (wire format).
void ns_build_header(ns_header_t *out_hdr_be,
                     uint8_t flags,
                     uint16_t opcode,
                     uint16_t status,
                     uint64_t req_id,
                     const uint8_t *body,
                     uint32_t body_len);

bool ns_validate_header_basic(const ns_header_t *hdr_be, uint32_t max_body_len);
bool ns_validate_checksum(const ns_header_t *hdr_be, const uint8_t *body, size_t body_len);

// Big-endian load/store (wire <-> host)
uint16_t ns_be16(const void *p);
uint32_t ns_be32(const void *p);
uint64_t ns_be64(const void *p);
void ns_put_be16(void *p, uint16_t v);
void ns_put_be32(void *p, uint32_t v);
void ns_put_be64(void *p, uint64_t v);


