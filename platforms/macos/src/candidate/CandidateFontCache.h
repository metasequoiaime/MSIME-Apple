#pragma once
#import <AppKit/AppKit.h>

// Resolves a font family name to the installed descriptor the candidate font is built from, or nil when no installed family has that exact name. The CoreText family match behind it runs a few times per candidate render, so the result - a miss included - is remembered per family name for the life of the process and forgotten whenever the set of registered fonts changes. Callers still read the family list from preferences on every render, so a family or fallback change written by another process takes effect without touching this cache. Safe to call from any thread.
NSFontDescriptor *MSIMEInstalledFontFamilyDescriptor(NSString *family);
