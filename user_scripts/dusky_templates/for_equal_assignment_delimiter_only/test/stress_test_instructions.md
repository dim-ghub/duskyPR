Dusky TUI Master Template - Stress Testing Guide

This guide details the specific edge cases implemented in stress_test_dusky.sh (Extreme Version) and what behaviors you should expect during testing.

1. Tab 0: "The Wall" (Massive List)

Objective: Test rendering performance and scrolling logic with large datasets.

Test: Scrolling through 250 items.

Action: Hold j (down) to scroll rapidly from item 0 to 249.

Expectation: The UI should remain responsive. The scroll indicator ▼ (more below) should update correctly showing [x/250].

Limit Check: Scroll to item #250. Ensure the list stops cleanly and doesn't crash or loop unexpectedly.

2. Tab 1: "The Abyss" (Deep Nesting)

Objective: Verify that the engine correctly parses blocks nested 6 levels deep.

Test: Reading values from level_0 down to level_5.

Logic Check: The engine uses key|immediate_parent_block for lookups.

Action: Modify "Level 6 (Depth 6)".

Expectation: The change should persist in stress_test_extreme.conf. Open the config file in a separate terminal and verify that val_l6 inside level_5 { ... } changes, and that indentation is preserved.

Edge Case: Verify that modifying a deep value doesn't accidentally modify a value with the same name in a shallower scope.

3. Tab 2: "Minefield" (Parser Traps)

Objective: Validate input sanitization and arithmetic handling.

Octal Traps (08/09)

Test: "Octal 08 (Trap)" and "Octal 09 (Trap)".

Context: In Bash, numbers starting with 0 are octal. 08 is invalid octal.

Action: Increase value of "Octal 08" (currently 8).

Expectation: It should increment to 9. If the engine fails to sanitize inputs (using 10#...), it will crash bash or error when attempting arithmetic on 08.

Floating Point Precision

Test: "Float Micro" (0.00001).

Action: Increment/Decrement.

Expectation: awk math should handle this correctly. Ensure it doesn't round to 0 unexpectedly.

Test: "Float Negative" (-50.5).

Expectation: Should handle negative signs correctly during read and write.

Missing/Empty Keys

Test: "Explicit Empty" (val_empty).

Expectation: Should show the value (e.g., "one") if set in config, or cycle correctly.

Test: "Missing Key" (val_missing).

Expectation: Should display ⚠ UNSET initially. If you toggle it, it should write the key to the global scope (end of file) because it has no block definition in register.

4. Tab 3: "Menus" (Drill Down)

Objective: Test context switching and variable scope sharing.

Test: "Deep Controls >".

Action: Press Enter to open.

Expectation: View switches to the submenu. You should see "Deep Value L5" and "Deep Value L6".

Logic Check: These items map to the same variables as in Tab 1 ("The Abyss"). Changing them here must reflect in Tab 1 (requires restart/reload to see cross-tab updates if cache isn't refreshed dynamically).

5. Tab 4: "Palette" (Hex/Hash parsing)

Objective: The ultimate test for the sub(/[[:space:]]+#.*$/, "", val) regex logic.

Standard Tests

Test: "Hex Standard" (#ffffff), "Hex Short" (#fff), "Hex Caps" (#AABBCC).

Expectation: Should display correctly.

The Traps (Critical)

Test: "Hash Space (Trap)" (# 998877).

Context: The config file has hex_space_after = # 998877.

Trap: The engine parser strips comments starting with space+hash.

Expectation: This value might appear as ⚠ UNSET or empty because the parser strips it thinking it's a comment. If it displays, verify that writing to it doesn't corrupt the file.

Test: "Hex Comment Spc" (#ff0000 # comment).

Expectation: The value should be #ff0000. The # comment must be stripped.

Test: "Hex Comment Tgt" (#00ff00#comment).

Trap: No space before the second hash.

Expectation: The value might be read as #00ff00#comment because the regex requires space before the hash. This tests if the regex is too strict or too loose.

Quotes & Formats

Test: "Hex Quoted Dbl" ("#123456").

Expectation: Should preserve quotes if the writer logic handles them, or strip them if sanitized.

Test: "Legacy 0x" (0xff00ff).

Expectation: Should be treated as a string/cycle option and displayed correctly.

6. Tab 5: "Root" (Root Level Config)

Objective: Test keys that exist outside of any block {}.

Test: "Root Performance" (performance).

Context: performance = on is at the very top of the config.

Expectation: The parser must correctly identify this key with an empty block definition ||.

Action: Toggle it.

Verification: Ensure it doesn't create a new entry at the bottom of the file or corrupt the top of the file.

7. Tab 6: "Void" (Empty Tab)

Objective: Test empty list handling.

Test: Switch to this tab.

Expectation: The UI should display an empty list. It should not crash. Scrolling keys should do nothing.

8. General Parser Robustness

Braces in Comments: The config file contains # Trap: braces in comments { } inside level_5.

Expectation: The parser's brace counting logic must ignore these. If it fails, the nesting depth of subsequent blocks (like traps or colors) will be wrong, and values won't load. If Tab 2 or Tab 4 items are ⚠ UNSET, the brace counting logic failed.
