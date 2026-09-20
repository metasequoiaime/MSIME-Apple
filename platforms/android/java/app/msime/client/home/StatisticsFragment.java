package app.msime.client.home;

import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.fragment.app.Fragment;
import com.google.android.material.tabs.TabLayout;
import app.msime.client.R;

/**
 * The 统计 tab: today and the running total, then a thirty-day trend and a day-per-cell calendar.
 *
 * The counts come from the shared typing-statistics store, which holds aggregate counts only -- never
 * the text that produced them. Nothing here is filled in with placeholder numbers: a store that has
 * never been written says so, because a zero and "not recording" mean different things to the reader.
 */
public final class StatisticsFragment extends Fragment {

    @Override public View onCreateView(@NonNull LayoutInflater inflater, @Nullable ViewGroup parent,
                                       @Nullable Bundle state) {
        return inflater.inflate(R.layout.page_statistics, parent, false);
    }

    @Override public void onViewCreated(@NonNull View view, @Nullable Bundle state) {
        TabLayout ranges = view.findViewById(R.id.statistics_ranges);
        for (String label : new String[] {"趋势", "类型", "模式", "方案"}) {
            ranges.addTab(ranges.newTab().setText(label));
        }

        TypingStatistics.Snapshot snapshot = TypingStatistics.read(requireContext());
        TextView today = view.findViewById(R.id.statistics_today);
        TextView total = view.findViewById(R.id.statistics_total);
        TextView state2 = view.findViewById(R.id.statistics_state);
        TrendChart trend = view.findViewById(R.id.statistics_trend);
        HeatmapView heatmap = view.findViewById(R.id.statistics_heatmap);

        if (snapshot == null) {
            today.setText("—");
            total.setText("—");
            state2.setVisibility(View.VISIBLE);
            state2.setText("还没有记录。开始用键盘输入后，这里会出现每日字符数；统计只保存聚合计数，不保存输入内容。");
            return;
        }
        today.setText(String.valueOf(snapshot.today));
        total.setText(String.valueOf(snapshot.total));
        state2.setVisibility(View.GONE);
        trend.setDaily(snapshot.daily);
        heatmap.setDaily(snapshot.daily);
    }
}
