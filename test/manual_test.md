# Manual Test for @file Macro

## Test Steps

1. Launch test environment:
   ```bash
   ./bin/nvim-test README.md
   ```

2. Try each command to verify macro expansion:

### Test 1: CCSend with @file
   ```vim
   :CCSend summarize @file
   ```
   Expected: Should send "summarize README.md" to Claude

### Test 2: CCAdd with @file
   ```vim
   :CCAdd review @file for improvements
   ```
   Expected: Staging buffer should contain "review README.md for improvements"

### Test 3: Multiple macros
   ```vim
   :CCSend compare @file with @filename and @filepath
   ```
   Expected: All three macros expand to the same path

### Test 4: Word boundaries (should NOT expand)
   ```vim
   :CCSend email me at contact@file.com
   ```
   Expected: Should send unchanged (email address preserved)

### Test 5: No file buffer
   ```vim
   :new
   :CCSend test @file expansion
   ```
   Expected: @file stays unchanged (no file associated with buffer)

### Test 6: Special buffer
   ```vim
   :CCAdd some text
   " Now in **claude-code** buffer
   :CCSend @file
   ```
   Expected: @file stays unchanged (special buffer)

### Test 7: @basename macro
   ```vim
   :CCSend rename @basename to something better
   ```
   Expected: Should send "rename README.md to something better"

### Test 8: @basename vs @file
   ```vim
   :CCSend compare @basename with full path @file
   ```
   Expected: Should show both filename only and full git-relative path

## Verification

After each command, check that:
- The macro was expanded correctly (or preserved when it should be)
- The path is relative to git root (since we're in a git repo)
- @basename expands to filename only (no directory path)
- No error messages appear
