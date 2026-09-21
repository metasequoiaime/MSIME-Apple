package app.msime.client;

import android.content.Context;

/**
 * 设置界面读得到的那点账号信息。
 *
 * <p>The keyboard creates a device-local anonymous identity the first time it needs the backend,
 * and that identity is all this host has: there is no sign-in on Android yet. Showing it is worth
 * doing anyway -- it is what the community catalogue is read with, and "没有登录" alone does not
 * tell the user whether anything reached the backend at all.
 */
public final class AccountIdentity {
    private AccountIdentity() {}

    /**
     * The anonymous subject, or an empty string when the keyboard has not created one.
     *
     * <p>Reading it never creates one: the identity should appear because the keyboard used the
     * backend, not because someone opened this tab.
     */
    public static String subject(Context context) {
        try {
            return new BackendAnonymousAccount(context).savedSubject();
        } catch (Exception | LinkageError error) {
            return "";
        }
    }

    /** A shortened form for a settings row; the full subject is not a secret but is not readable. */
    public static String shortSubject(String subject) {
        if (subject == null || subject.isEmpty()) return "";
        return subject.length() <= 14 ? subject : subject.substring(0, 14) + "…";
    }
}
