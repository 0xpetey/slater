# Slater

A macOS utility that translates the text inside a box the user draws on the screen, from a chosen source language into a chosen target language, entirely on-device.

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

**Source language**:
The language the user has chosen to read off the screen. Japanese by default (English on a Mac that runs in Japanese), and the one Slater is built and tested for; it must be one macOS can translate on-device and Vision can read.
_Avoid_: Input language, from-language

**Target language**:
The language translations are written in (English by default; Japanese on a Mac that runs in Japanese).
_Avoid_: Output language, to-language

**Source Block**:
A Block that contains at least one character of the source language's script (for Japanese: hiragana, katakana or kanji). Only Source Blocks are translated, and the whole Block is translated, including any numbers or target-language words mixed into it.
_Avoid_: Japanese Block, translatable block

**Low-confidence Block**:
A Source Block that OCR may have misread. It is still translated, but it's marked so the user knows to check the translation against the original.
_Avoid_: Uncertain block, bad OCR

**Passthrough Block**:
A Block with no characters of the source language's script, such as a part number, an amount or text already in the target language. It is shown exactly as it was captured and is never translated.
_Avoid_: Skipped block, ignored text
