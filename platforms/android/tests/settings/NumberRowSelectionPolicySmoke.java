public final class NumberRowSelectionPolicySmoke {
    public static void main(String[] args) {
        if (app.msime.client.NumberRowSelectionPolicy.slotForKeyCode(8, true) != 0)
            throw new AssertionError("1");
        if (app.msime.client.NumberRowSelectionPolicy.slotForKeyCode(16, true) != 8)
            throw new AssertionError("9");
        if (app.msime.client.NumberRowSelectionPolicy.slotForKeyCode(7, true) != -1)
            throw new AssertionError("zero");
        if (app.msime.client.NumberRowSelectionPolicy.slotForKeyCode(8, false) != -1)
            throw new AssertionError("disabled");
        System.out.println("Android number-row candidate selection passed");
    }
}
