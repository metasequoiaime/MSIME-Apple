import app.msime.client.KeyboardGeometry;

public final class KeyboardGeometrySmoke {
    static void check(boolean condition) { if (!condition) throw new AssertionError(); }

    public static void main(String[] args) {
        check(KeyboardGeometry.keySpacing(-1) == 60);
        check(KeyboardGeometry.rowSpacing(-1) == 70);
        check(KeyboardGeometry.keySpacing(29) == 30);
        check(KeyboardGeometry.keySpacing(61) == 60);
        check(KeyboardGeometry.rowSpacing(39) == 40);
        check(KeyboardGeometry.rowSpacing(101) == 100);
        check(KeyboardGeometry.keySpacing(35) == 35);
        check(KeyboardGeometry.rowSpacing(95) == 95);
        check(KeyboardGeometry.display(35).equals("3.5"));
        check(KeyboardGeometry.display(100).equals("10.0"));
        check(KeyboardGeometry.halfGapPixels(60, 1) == 3);
        check(KeyboardGeometry.halfGapPixels(35, 2) == 4);
        check(KeyboardGeometry.halfGapPixels(60, Float.NaN) == 0);
        System.out.println("Android keyboard geometry: Apple defaults, bounds and precision passed");
    }
}
