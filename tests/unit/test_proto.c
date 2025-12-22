#include "proto.h"
#
#include <assert.h>
#include <stdio.h>
#include <string.h>
#
static void test_be_helpers(void) {
  uint8_t buf[8];
  ns_put_be16(buf, 0x1234u);
  assert(ns_be16(buf) == 0x1234u);

  ns_put_be32(buf, 0x89ABCDEFu);
  assert(ns_be32(buf) == 0x89ABCDEFu);

  ns_put_be64(buf, 0x0123456789ABCDEFull);
  assert(ns_be64(buf) == 0x0123456789ABCDEFull);
}

static void test_crc_and_checksum(void) {
  const char *msg = "hello world";
  uint32_t c1 = ns_crc32(msg, strlen(msg));
  uint32_t c2 = ns_crc32(msg, strlen(msg));
  assert(c1 == c2);

  ns_header_t hdr;
  memset(&hdr, 0, sizeof(hdr));
  ns_build_header(&hdr, 0, OP_HELLO, ST_OK, 42, (const uint8_t *)msg, (uint32_t)strlen(msg));
  assert(ns_validate_header_basic(&hdr, 65536));
  assert(ns_validate_checksum(&hdr, (const uint8_t *)msg, strlen(msg)));
}

static void test_xor_crypt(void) {
  uint8_t data[] = {1, 2, 3, 4, 5};
  uint8_t orig[sizeof(data)];
  memcpy(orig, data, sizeof(data));

  ns_xor_crypt(data, sizeof(data), NS_XOR_KEY);
  assert(memcmp(data, orig, sizeof(data)) != 0);

  ns_xor_crypt(data, sizeof(data), NS_XOR_KEY);
  assert(memcmp(data, orig, sizeof(data)) == 0);
}

int main(void) {
  test_be_helpers();
  test_crc_and_checksum();
  test_xor_crypt();
  printf("test_proto: OK\n");
  return 0;
}


