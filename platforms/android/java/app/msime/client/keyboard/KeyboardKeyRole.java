package app.msime.client;

/**
 * 一个键在皮肤里扮演的视觉角色。
 *
 * <p>The style pass used to carry a single boolean: a key wore the key face, and everything else
 * wore the filled accent face. That is why the shortcut strip came out as a row of solid green
 * blocks. A button now says which face it wants, so the capless treatments the shared design uses
 * for toolbars, sidebars and paging controls are expressible instead of being approximated by the
 * one filled face.
 */
public enum KeyboardKeyRole {
    /** A key cap: the skin's key background and label colour. */
    KEY,
    /** An emphasized key such as 换行: the skin's filled action face. */
    ACCENT,
    /** A key without a cap, keeping the key label colour; the nine-key punctuation column. */
    PLAIN,
    /** A capless control drawn in the accent colour: the toolbar glyphs and the paging controls. */
    GLYPH;

    /** Whether the skin's cap background, border and shadow apply to this role. */
    public boolean drawsCap() { return this == KEY || this == ACCENT; }

    /** Whether the label takes the accent colour rather than the skin's key label colour. */
    public boolean usesAccentLabel() { return this == GLYPH; }

    /** Whether the key spacing setting insets this role inside its row. */
    public boolean followsKeySpacing() { return this != GLYPH; }
}
