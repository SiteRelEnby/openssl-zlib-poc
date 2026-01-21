#!/bin/bash
# Run the zlib DSO init bug test

echo "=============================================="
echo "OpenSSL zlib DSO initialization bug test"
echo "=============================================="
echo ""

# Check if libz is available (it shouldn't be in the test image)
echo "Checking for libz.so..."
if ldconfig -p | grep -q libz; then
    echo "WARNING: libz.so is installed! This test requires it to be absent."
    echo "         The test may not accurately demonstrate the bug."
else
    echo "libz.so is NOT installed (expected for this test)"
fi
echo ""

# Run the test
echo "Running test..."
echo ""
/test_zlib_init

exit_code=$?
echo ""
echo "Exit code: $exit_code"

if [ $exit_code -eq 139 ] || [ $exit_code -eq 134 ] || [ $exit_code -eq 11 ]; then
    echo ""
    echo "*** CRASHED (SIGSEGV) - This demonstrates the BUG ***"
    echo "The program crashed because OpenSSL returned a zlib method"
    echo "with NULL function pointers, which were then dereferenced."
fi
