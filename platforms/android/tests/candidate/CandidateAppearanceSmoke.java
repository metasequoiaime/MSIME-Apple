import app.msime.client.CandidateAppearance;
import java.util.List;

public final class CandidateAppearanceSmoke {
    static void check(boolean condition) { if (!condition) throw new AssertionError(); }

    public static void main(String[] args) throws Exception {
        check(!CandidateAppearance.isHorizontal("vertical"));
        check(CandidateAppearance.isHorizontal("horizontal"));
        check(!CandidateAppearance.isHorizontal("untrusted"));
        check(CandidateAppearance.fontSize(12) == 12);
        check(CandidateAppearance.fontSize(32) == 32);
        check(CandidateAppearance.fontSize(11) == 16);
        check(CandidateAppearance.fontSize(33) == 16);
        for (String skin : new String[] {"fluent", "wechat", "graphite", "willow_green"}) {
            CandidateAppearance.Palette light = CandidateAppearance.fromValues(
                skin, "light", "system", true, "", "", "", "", "", "", "");
            CandidateAppearance.Palette dark = CandidateAppearance.fromValues(
                skin, "dark", "system", false, "", "", "", "", "", "", "");
            check(light.surface() != dark.surface());
            check(skin.equals(light.id()));
        }
        check(CandidateAppearance.fromValues(
            "untrusted", "light", "system", false, "", "", "", "", "", "", "")
            .id().equals("willow_green"));
        check(CandidateAppearance.fromValues(
            "willow_green", "untrusted", "system", true, "", "", "", "", "", "", "")
            .surface() == CandidateAppearance.fromValues(
                "willow_green", "dark", "system", false, "", "", "", "", "", "", "")
                .surface());
        CandidateAppearance.Palette palette = CandidateAppearance.fromValues(
            "wechat", "light", "system", true, "#123456", "", "#abcdef", "#010203",
            "#040506", "#070809", "#0a0b0c");
        check(palette.text() == 0xff123456);
        check(palette.number() == 0x9d123456);
        check(palette.accent() == 0xffabcdef);
        check(palette.selected() == 0xff010203);
        check(palette.hover() == 0xff040506);
        check(palette.surface() == 0xff070809);
        check(palette.border() == 0xff0a0b0c);
        check(CandidateAppearance.fromValues(
            "willow_green", "light", "system", false, "bad", "", "", "", "", "", "")
            .text() != 0xffbadbad);
        check((CandidateAppearance.fromValues(
            "graphite", "light", "system", false, "", "", "", "", "", "", "")
            .selected() >>> 24) == 0);
        CandidateAppearance.Palette fonts = CandidateAppearance.fromValues(
            "fluent", "light", "system", false, "", "", "", "", "", "", "",
            "Noto Sans CJK", "Noto Sans Mono", List.of("Microsoft YaHei", "Noto Sans SC"));
        check("Noto Sans CJK".equals(fonts.fontFamily()));
        check("Noto Sans Mono".equals(fonts.englishFont()));
        check("Noto Sans Mono".equals(fonts.preferredFont()));
        check(fonts.fallbackFonts().equals(List.of("Microsoft YaHei", "Noto Sans SC")));
        CandidateAppearance.Palette invalidFonts = CandidateAppearance.fromValues(
            "fluent", "light", "system", false, "", "", "", "", "", "", "",
            "", "bad\nfont", List.of("", "x".repeat(129)));
        check("Noto Sans SC".equals(invalidFonts.fontFamily()));
        check(invalidFonts.englishFont().isEmpty());
        check(invalidFonts.fallbackFonts().equals(List.of("Noto Sans SC", "Microsoft YaHei")));
        System.out.println("Android candidate appearance: skins, themes, overrides, alpha and fallback passed");
    }
}
