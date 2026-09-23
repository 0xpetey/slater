# Slater

A macOS utility that translates the Japanese text inside a box the user draws on the screen, entirely on-device.

## Language

**Shot**:
The result of one hotkey press and drag: a frozen image of the selected box, its Blocks and their translations, shown in its own floating window. It stays open until the user closes it.
_Avoid_: Translation-shot, snip, overlay, result

**Capture**:
The act of grabbing the screen's pixels at the moment the hotkey is pressed. A Capture is the raw input to a Shot, not the Shot itself.
_Avoid_: Screenshot (as a noun for a Shot)

**Line**:
A single run of text as it appears on screen, before any merging: a row of horizontal writing or a column of vertical writing (縦書き).
_Avoid_: Observation, row

**Block**:
One or more Lines that continue one another and read as one unit, such as a paragraph or a wrapped cell, and are translated together. In horizontal writing the Lines are stacked; in vertical writing they are columns running right to left. A Block never joins text across the direction of writing, so separate table cells, form labels and page columns are always separate Blocks.
_Avoid_: Paragraph, chunk, region

**Japanese Block**:
A Block that contains at least one hiragana, katakana or kanji character. Only Japanese Blocks are translated, and the whole Block is translated, including any English or numbers mixed into it.

**Low-confidence Block**:
A Japanese Block that OCR may have misread. It is still translated, but it's marked so the user knows to check the translation against the original.
_Avoid_: Uncertain block, bad OCR

**Passthrough Block**:
A Block with no Japanese characters, such as a part number, an amount or English text. It is shown exactly as it was captured and is never translated.
_Avoid_: Skipped block, ignored text
