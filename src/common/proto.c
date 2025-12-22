#include "proto.h"

#include <string.h>

uint16_t ns_be16(const void *p) {
  const uint8_t *b = (const uint8_t *)p;
  return (uint16_t)((uint16_t)b[0] << 8u | (uint16_t)b[1]);
}
uint32_t ns_be32(const void *p) {
  const uint8_t *b = (const uint8_t *)p;
  return ((uint32_t)b[0] << 24u) | ((uint32_t)b[1] << 16u) | ((uint32_t)b[2] << 8u) | (uint32_t)b[3];
}
uint64_t ns_be64(const void *p) {
  const uint8_t *b = (const uint8_t *)p;
  return ((uint64_t)b[0] << 56u) | ((uint64_t)b[1] << 48u) | ((uint64_t)b[2] << 40u) | ((uint64_t)b[3] << 32u) |
         ((uint64_t)b[4] << 24u) | ((uint64_t)b[5] << 16u) | ((uint64_t)b[6] << 8u) | (uint64_t)b[7];
}
void ns_put_be16(void *p, uint16_t v) {
  uint8_t *b = (uint8_t *)p;
  b[0] = (uint8_t)(v >> 8u);
  b[1] = (uint8_t)(v & 0xffu);
}
void ns_put_be32(void *p, uint32_t v) {
  uint8_t *b = (uint8_t *)p;
  b[0] = (uint8_t)(v >> 24u);
  b[1] = (uint8_t)(v >> 16u);
  b[2] = (uint8_t)(v >> 8u);
  b[3] = (uint8_t)(v & 0xffu);
}
void ns_put_be64(void *p, uint64_t v) {
  uint8_t *b = (uint8_t *)p;
  b[0] = (uint8_t)(v >> 56u);
  b[1] = (uint8_t)(v >> 48u);
  b[2] = (uint8_t)(v >> 40u);
  b[3] = (uint8_t)(v >> 32u);
  b[4] = (uint8_t)(v >> 24u);
  b[5] = (uint8_t)(v >> 16u);
  b[6] = (uint8_t)(v >> 8u);
  b[7] = (uint8_t)(v & 0xffu);
}

// CRC32 (polynomial 0xEDB88320) - small tableless implementation (fast enough for this project)
static uint32_t crc32_update(uint32_t crc, const void *data, size_t len) {
  const uint8_t *p = (const uint8_t *)data;
  for (size_t i = 0; i < len; i++) {
    crc ^= (uint32_t)p[i];
    for (int k = 0; k < 8; k++) {
      uint32_t mask = (uint32_t)-(int)(crc & 1u);
      crc = (crc >> 1u) ^ (0xEDB88320u & mask);
    }
  }
  return crc;
}

uint32_t ns_crc32(const void *data, size_t len) {
  uint32_t crc = 0xFFFFFFFFu;
  crc = crc32_update(crc, data, len);
  return ~crc;
}

uint32_t ns_frame_checksum(const ns_header_t *hdr_be, const uint8_t *body, size_t body_len) {
  // checksum is CRC32(header_without_checksum + body)
  ns_header_t tmp;
  memcpy(&tmp, hdr_be, sizeof(tmp));
  tmp.checksum = 0;

  uint32_t crc = 0xFFFFFFFFu;
  crc = crc32_update(crc, &tmp, sizeof(tmp));
  if (body && body_len) crc = crc32_update(crc, body, body_len);
  return ~crc;
}

void ns_xor_crypt(uint8_t *data, size_t len, uint32_t key) {
  if (!data || len == 0) return;
  uint8_t k[4];
  ns_put_be32(k, key);
  for (size_t i = 0; i < len; i++) {
    data[i] ^= k[i % 4];
  }
}

void ns_build_header(ns_header_t *out_hdr_be,
                     uint8_t flags,
                     uint16_t opcode,
                     uint16_t status,
                     uint64_t req_id,
                     const uint8_t *body,
                     uint32_t body_len) {
  memset(out_hdr_be, 0, sizeof(*out_hdr_be));
  ns_put_be16(&out_hdr_be->magic, (uint16_t)NS_MAGIC);
  out_hdr_be->version = (uint8_t)NS_VERSION;
  out_hdr_be->flags = flags;
  ns_put_be16(&out_hdr_be->header_len, (uint16_t)sizeof(ns_header_t));
  ns_put_be32(&out_hdr_be->body_len, body_len);
  ns_put_be16(&out_hdr_be->opcode, opcode);
  ns_put_be16(&out_hdr_be->status, status);
  ns_put_be64(&out_hdr_be->req_id, req_id);
  out_hdr_be->checksum = 0;
  uint32_t sum = ns_frame_checksum(out_hdr_be, body, body_len);
  ns_put_be32(&out_hdr_be->checksum, sum);
}

bool ns_validate_header_basic(const ns_header_t *hdr_be, uint32_t max_body_len) {
  if (ns_be16(&hdr_be->magic) != (uint16_t)NS_MAGIC) return false;
  if (hdr_be->version != (uint8_t)NS_VERSION) return false;
  if (ns_be16(&hdr_be->header_len) != (uint16_t)sizeof(ns_header_t)) return false;
  uint32_t bl = ns_be32(&hdr_be->body_len);
  if (bl > max_body_len) return false;
  return true;
}

bool ns_validate_checksum(const ns_header_t *hdr_be, const uint8_t *body, size_t body_len) {
  uint32_t want = ns_be32(&hdr_be->checksum);
  uint32_t got = ns_frame_checksum(hdr_be, body, body_len);
  return want == got;
}


