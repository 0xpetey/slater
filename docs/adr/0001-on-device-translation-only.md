# On-device only, and nothing kept by default

Slater is used on confidential work documents, so captured screen content, recognized text and translations must never leave the Mac. OCR uses Apple Vision and translation uses Apple's on-device Translation framework, even though a cloud model would translate dense business Japanese better. A cloud engine may be added only after management explicitly approves it, and then only as an opt-in setting. On-device stays the default.

For the same reason, Shots exist only in memory. Slater never writes Captures, Shots or translations to disk on its own: there is no history, no cache, nothing is restored on relaunch, and recognized text and translations are never written to the system log. The only way anything is written to disk is the user explicitly saving a Shot, to a location they choose in a save dialog.
