package app.msime.client.home;

import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.fragment.app.Fragment;
import app.msime.client.R;

/**
 * The 我的 tab: the account, the icon choice, and what is kept in the cloud.
 *
 * The rows are the Apple app's. Their destinations are not built on Android yet, so each one is shown
 * disabled rather than opening an empty screen; the account card reads the anonymous identity the
 * keyboard already creates rather than claiming a signed-in user.
 */
public final class AccountFragment extends Fragment {

    @Override public View onCreateView(@NonNull LayoutInflater inflater, @Nullable ViewGroup parent,
                                       @Nullable Bundle state) {
        return inflater.inflate(R.layout.page_account, parent, false);
    }

    @Override public void onViewCreated(@NonNull View view, @Nullable Bundle state) {
        // Nothing to bind yet: every row is a placeholder until its destination exists.
    }
}
