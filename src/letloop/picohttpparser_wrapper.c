/*
 * picohttpparser wrapper for Chez Scheme FFI
 *
 * Converts absolute pointers returned by phr_parse_request/phr_parse_response
 * into buffer-relative offsets, making them trivial to read from Scheme using
 * bytevector-u64-ref / bytevector-s32-ref.
 *
 * Output buffer layout (all offsets relative to input buf):
 *
 *   Bytes   Field
 *   [0..7]  method_offset (size_t)
 *   [8..15] method_len (size_t)
 *   [16..23] path_offset (size_t)
 *   [24..31] path_len (size_t)
 *   [32..35] minor_version (int32)
 *   [36..39] padding
 *   [40..47] num_headers (size_t)
 *   [48..]  per-header entries, each 32 bytes:
 *           [+0..+7]   name_offset (size_t)
 *           [+8..+15]  name_len (size_t)
 *           [+16..+23] value_offset (size_t)
 *           [+24..+31] value_len (size_t)
 *
 * For response parsing:
 *   [0..3]  status (int32)
 *   [4..7]  minor_version (int32)
 *   [8..15] msg_offset (size_t)
 *   [16..23] msg_len (size_t)
 *   [24..31] num_headers (size_t)
 *   [32..]  per-header entries (same 32-byte layout)
 */

#include "picohttpparser.c"

#define PHR_MAX_HEADERS 100

int phr_parse_request_wrapper(const char *buf, size_t len,
                               char *out, size_t max_headers,
                               size_t last_len)
{
    const char *method, *path;
    size_t method_len, path_len;
    int minor_version;
    struct phr_header headers[PHR_MAX_HEADERS];
    size_t num_headers;

    if (max_headers > PHR_MAX_HEADERS)
        max_headers = PHR_MAX_HEADERS;
    num_headers = max_headers;

    int ret = phr_parse_request(buf, len,
                                 &method, &method_len,
                                 &path, &path_len,
                                 &minor_version,
                                 headers, &num_headers,
                                 last_len);

    if (ret > 0) {
        /* method */
        *(size_t *)(out + 0) = (size_t)(method - buf);
        *(size_t *)(out + 8) = method_len;
        /* path */
        *(size_t *)(out + 16) = (size_t)(path - buf);
        *(size_t *)(out + 24) = path_len;
        /* minor version */
        *(int *)(out + 32) = minor_version;
        /* padding at 36..39 is left as-is */
        /* num_headers */
        *(size_t *)(out + 40) = num_headers;
        /* headers */
        for (size_t i = 0; i < num_headers; i++) {
            size_t base = 48 + i * 32;
            if (headers[i].name != NULL) {
                *(size_t *)(out + base + 0) = (size_t)(headers[i].name - buf);
                *(size_t *)(out + base + 8) = headers[i].name_len;
            } else {
                *(size_t *)(out + base + 0) = 0;
                *(size_t *)(out + base + 8) = 0;
            }
            *(size_t *)(out + base + 16) = (size_t)(headers[i].value - buf);
            *(size_t *)(out + base + 24) = headers[i].value_len;
        }
    }

    return ret;
}

int phr_parse_response_wrapper(const char *buf, size_t len,
                                char *out, size_t max_headers,
                                size_t last_len)
{
    int minor_version, status;
    const char *msg;
    size_t msg_len;
    struct phr_header headers[PHR_MAX_HEADERS];
    size_t num_headers;

    if (max_headers > PHR_MAX_HEADERS)
        max_headers = PHR_MAX_HEADERS;
    num_headers = max_headers;

    int ret = phr_parse_response(buf, len,
                                  &minor_version, &status,
                                  &msg, &msg_len,
                                  headers, &num_headers,
                                  last_len);

    if (ret > 0) {
        *(int *)(out + 0) = status;
        *(int *)(out + 4) = minor_version;
        *(size_t *)(out + 8) = (msg != NULL) ? (size_t)(msg - buf) : 0;
        *(size_t *)(out + 16) = msg_len;
        *(size_t *)(out + 24) = num_headers;
        for (size_t i = 0; i < num_headers; i++) {
            size_t base = 32 + i * 32;
            if (headers[i].name != NULL) {
                *(size_t *)(out + base + 0) = (size_t)(headers[i].name - buf);
                *(size_t *)(out + base + 8) = headers[i].name_len;
            } else {
                *(size_t *)(out + base + 0) = 0;
                *(size_t *)(out + base + 8) = 0;
            }
            *(size_t *)(out + base + 16) = (size_t)(headers[i].value - buf);
            *(size_t *)(out + base + 24) = headers[i].value_len;
        }
    }

    return ret;
}
