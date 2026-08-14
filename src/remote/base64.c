#include "base64.h"
#include <stdlib.h>

static const char base64_table[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

char *base64_encode(const uint8_t *data, size_t input_length, size_t *output_length) {
    if (!data) return NULL;

    size_t out_len = 4 * ((input_length + 2) / 3);
    char *encoded_data = malloc(out_len + 1);
    if (!encoded_data) return NULL;

    size_t i = 0, j = 0;
    while (i < input_length) {
        uint32_t octet_a = i < input_length ? data[i++] : 0;
        uint32_t octet_b = i < input_length ? data[i++] : 0;
        uint32_t octet_c = i < input_length ? data[i++] : 0;

        uint32_t triple = (octet_a << 16) + (octet_b << 8) + octet_c;

        encoded_data[j++] = base64_table[(triple >> 18) & 0x3F];
        encoded_data[j++] = base64_table[(triple >> 12) & 0x3F];
        encoded_data[j++] = (i > input_length + 1) ? '=' : base64_table[(triple >> 6) & 0x3F];
        encoded_data[j++] = (i > input_length) ? '=' : base64_table[triple & 0x3F];
    }

    encoded_data[out_len] = '\0';
    if (output_length) *output_length = out_len;
    return encoded_data;
}
