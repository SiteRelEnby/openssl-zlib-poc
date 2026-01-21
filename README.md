# OpenSSL zlib DSO Initialization Bug PoC

This demonstrates a bug in OpenSSL 3.6.0 (and earlier) where `ossl_comp_zlib_init()`
returns success (1) even when the zlib DSO fails to load, causing NULL pointer
dereferences when certificate compression is used.

https://github.com/openssl/openssl/pull/29699

## The Bug

In `crypto/comp/c_zlib.c`, the `ossl_comp_zlib_init()` function:

```c
DEFINE_RUN_ONCE_STATIC(ossl_comp_zlib_init)
{
# ifdef ZLIB_SHARED
    zlib_dso = DSO_load(NULL, LIBZ, NULL, 0);
    if (zlib_dso != NULL) {
        p_compress = (compress_ft) DSO_bind_func(zlib_dso, "compress");
        p_uncompress = (compress_ft) DSO_bind_func(zlib_dso, "uncompress");
        // ... more bindings

        if (p_compress == NULL || ...) {  // <-- This check is INSIDE the if block!
            ossl_comp_zlib_cleanup();
            return 0;
        }
    }
# endif
    return 1;  // <-- Returns success even if DSO_load() failed!
}
```

When `ZLIB_SHARED` is defined and `DSO_load()` fails (returns NULL):
1. The `if (zlib_dso != NULL)` block is skipped entirely
2. All function pointers remain NULL
3. The function returns 1 (success)
4. `COMP_zlib_oneshot()` returns `&zlib_oneshot_method`
5. When compression is attempted, NULL function pointers are dereferenced → **CRASH**

## The Fix

Move the NULL check **outside** the `if (zlib_dso != NULL)` block, consistent with
how brotli and zstd handle this:

```c
    if (zlib_dso != NULL) {
        p_compress = ...;
        // ... bindings
    }

    // Check moved OUTSIDE the block - catches DSO load failure
    if (p_compress == NULL || ...) {
        ossl_comp_zlib_cleanup();
        return 0;
    }
```

## Running the PoC

### Build and run the BUGGY version:
```bash
./build.sh buggy
```

Expected output:
```
Test 2: COMP_zlib_oneshot() check
  FAIL: COMP_zlib_oneshot() returned non-NULL!
...
*** CRASHED (SIGSEGV) - This demonstrates the BUG ***
```

### Build and run the FIXED version:
```bash
./build.sh fixed
```

Expected output:
```
Test 2: COMP_zlib_oneshot() check
  PASS: COMP_zlib_oneshot() returned NULL (zlib not available)
...
RESULT: FIXED - OpenSSL correctly reports zlib as unavailable
```

## Impact

This bug affects any application using OpenSSL with:
1. `zlib-dynamic` enabled (the default when zlib is enabled)
2. Running in an environment where libz.so is not installed
3. Using TLS 1.3 certificate compression (RFC 8879)

When a TLS 1.3 peer sends a compressed certificate and the server attempts to
decompress it, the server crashes with SIGSEGV.
