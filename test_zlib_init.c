/*
 * Test program to demonstrate OpenSSL zlib DSO initialization bug.
 *
 * Bug: When ZLIB_SHARED is defined and DSO_load() fails (because libz.so
 * is not available), ossl_comp_zlib_init() still returns 1 (success).
 * This causes COMP_zlib_oneshot() to return a valid-looking method,
 * but the internal function pointers (p_compress, p_uncompress) are NULL.
 *
 * When certificate compression tries to use these methods, it dereferences
 * NULL function pointers causing SIGSEGV.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/comp.h>
#include <openssl/bio.h>

int main(int argc, char *argv[])
{
    printf("OpenSSL zlib DSO init bug test\n");
    printf("OpenSSL version: %s\n\n", OPENSSL_VERSION_TEXT);

    /* Initialize OpenSSL */
    SSL_library_init();
    OpenSSL_add_all_algorithms();
    SSL_load_error_strings();

    /* Test 1: Check if BIO_f_zlib() returns NULL (correct) or non-NULL (buggy) */
    printf("Test 1: BIO_f_zlib() availability check\n");
    const BIO_METHOD *zlib_bio = BIO_f_zlib();
    if (zlib_bio == NULL) {
        printf("  PASS: BIO_f_zlib() returned NULL (zlib not available)\n");
    } else {
        printf("  FAIL: BIO_f_zlib() returned non-NULL but zlib DSO failed to load!\n");
        printf("        This means ossl_comp_zlib_init() reported success incorrectly.\n");
    }

    /* Test 2: Check COMP_zlib_oneshot() */
    printf("\nTest 2: COMP_zlib_oneshot() check\n");
    COMP_METHOD *oneshot = COMP_zlib_oneshot();
    if (oneshot == NULL) {
        printf("  PASS: COMP_zlib_oneshot() returned NULL (zlib not available)\n");
    } else {
        printf("  FAIL: COMP_zlib_oneshot() returned non-NULL!\n");
        printf("        This is the bug - method looks valid but internal pointers are NULL.\n");
    }

    /* Test 3: Try to actually use the compression - this will crash on buggy version */
    if (oneshot != NULL) {
        printf("\nTest 3: Attempting to use compression (will crash on buggy version)\n");
        printf("  Creating COMP_CTX...\n");

        COMP_CTX *ctx = COMP_CTX_new(oneshot);
        if (ctx == NULL) {
            printf("  COMP_CTX_new() returned NULL - partial failure\n");
        } else {
            printf("  COMP_CTX created, attempting compression...\n");

            /* This data will be compressed */
            unsigned char in_data[] = "Hello, World! This is test data for compression.";
            unsigned char out_data[1024];

            /* This call will dereference NULL p_compress pointer -> CRASH */
            printf("  Calling COMP_compress_block() - THIS WILL CRASH ON BUGGY VERSION\n");
            int ret = COMP_compress_block(ctx, out_data, sizeof(out_data),
                                          in_data, sizeof(in_data));

            /* We should never reach here on the buggy version */
            printf("  COMP_compress_block returned: %d\n", ret);
            COMP_CTX_free(ctx);
        }
    }

    printf("\n=== Test completed ===\n");

    if (zlib_bio != NULL || oneshot != NULL) {
        printf("RESULT: BUGGY - OpenSSL incorrectly reports zlib as available\n");
        return 1;
    } else {
        printf("RESULT: FIXED - OpenSSL correctly reports zlib as unavailable\n");
        return 0;
    }
}
