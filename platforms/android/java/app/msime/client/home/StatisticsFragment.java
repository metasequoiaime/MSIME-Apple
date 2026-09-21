package app.msime.client.home;

import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.fragment.app.Fragment;
import app.msime.client.R;
import app.msime.client.TypingStatisticsModel;
import app.msime.client.TypingStatisticsModel.Section;
import com.google.android.material.button.MaterialButton;
import com.google.android.material.chip.Chip;
import com.google.android.material.chip.ChipGroup;
import com.google.android.material.dialog.MaterialAlertDialogBuilder;
import com.google.android.material.materialswitch.MaterialSwitch;
import com.google.android.material.tabs.TabLayout;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

/**
 * The 统计 tab: today and the running total, then one of four views over the same counts.
 *
 * The counts come from the shared typing-statistics store, which holds aggregate counts only --
 * never the text that produced them. Nothing here is filled in with placeholder numbers: a store
 * that has never been written says so, because a zero and "not recording" mean different things to
 * the reader.
 */
public final class StatisticsFragment extends Fragment {
    /** 趋势默认画 30 天；记录不足 30 天就画到最早那条。 */
    private static final int DEFAULT_TREND_DAYS = 30;
    private static final int MIN_TREND_DAYS = 7;

    private static final Map<String, String> RETENTIONS = retentions();

    private Section section = Section.TREND;
    @Nullable private TypingStatisticsModel statistics;
    private boolean applyingState;

    @Override public View onCreateView(@NonNull LayoutInflater inflater, @Nullable ViewGroup parent,
                                       @Nullable Bundle state) {
        return inflater.inflate(R.layout.page_statistics, parent, false);
    }

    @Override public void onViewCreated(@NonNull View view, @Nullable Bundle state) {
        TabLayout ranges = view.findViewById(R.id.statistics_ranges);
        for (Section value : Section.values()) ranges.addTab(ranges.newTab().setText(value.tab()));
        ranges.addOnTabSelectedListener(new TabLayout.OnTabSelectedListener() {
            @Override public void onTabSelected(TabLayout.Tab tab) {
                section = Section.values()[tab.getPosition()];
                render();
            }

            @Override public void onTabUnselected(TabLayout.Tab tab) {}

            @Override public void onTabReselected(TabLayout.Tab tab) {}
        });

        ChipGroup retention = view.findViewById(R.id.statistics_retention);
        for (Map.Entry<String, String> entry : RETENTIONS.entrySet()) {
            Chip chip = new Chip(requireContext());
            chip.setText(entry.getValue());
            chip.setTag(entry.getKey());
            chip.setCheckable(true);
            chip.setId(View.generateViewId());
            retention.addView(chip);
        }
        retention.setOnCheckedStateChangeListener((group, ids) -> {
            if (applyingState || ids.isEmpty()) return;
            View chip = group.findViewById(ids.get(0));
            if (chip == null) return;
            String value = String.valueOf(chip.getTag());
            HostTask.run(this, context -> HostStore.setStatisticsRetention(context, value),
                this::adopt);
        });

        MaterialSwitch enabled = view.findViewById(R.id.statistics_enabled);
        enabled.setOnCheckedChangeListener((button, checked) -> {
            if (applyingState) return;
            HostTask.run(this, context -> HostStore.setStatisticsEnabled(context, checked),
                this::adopt);
        });

        MaterialButton reset = view.findViewById(R.id.statistics_reset);
        reset.setOnClickListener(ignored -> new MaterialAlertDialogBuilder(requireContext())
            .setTitle("清除全部统计")
            .setMessage("今日、累计和全部分类计数都会归零，且无法恢复。键盘会从下一次输入重新开始记录。")
            .setNegativeButton("取消", null)
            .setPositiveButton("清除", (dialog, which) -> HostTask.run(this,
                context -> HostStore.resetStatistics(context), this::adopt))
            .show());

        reload();
    }

    @Override public void onResume() {
        super.onResume();
        // The keyboard is a separate process and has been recording while this screen was away.
        if (statistics != null) reload();
    }

    private void reload() {
        HostTask.run(this, HostStore::loadStatistics, this::adopt);
    }

    private void adopt(@Nullable TypingStatisticsModel value) {
        if (value != null) statistics = value;
        render();
    }

    private void render() {
        View view = getView();
        if (view == null) return;
        TextView today = view.findViewById(R.id.statistics_today);
        TextView total = view.findViewById(R.id.statistics_total);
        TextView notice = view.findViewById(R.id.statistics_state);
        View trendSection = view.findViewById(R.id.statistics_trend_section);
        View distributionSection = view.findViewById(R.id.statistics_distribution_section);

        if (statistics == null) {
            today.setText("—");
            total.setText("—");
            notice.setVisibility(View.VISIBLE);
            notice.setText("还没有记录。开始用键盘输入后，这里会出现每日字符数；统计只保存聚合计数，不保存输入内容。");
            trendSection.setVisibility(View.GONE);
            distributionSection.setVisibility(View.GONE);
            return;
        }

        String day = LocalDate.now().toString();
        today.setText(String.valueOf(statistics.count(day)));
        total.setText(String.valueOf(statistics.total()));
        notice.setVisibility(statistics.enabled() ? View.GONE : View.VISIBLE);
        notice.setText("记录已关闭。已有的计数保留在本机，新的输入不再计入。");

        applyingState = true;
        MaterialSwitch enabled = view.findViewById(R.id.statistics_enabled);
        enabled.setChecked(statistics.enabled());
        ChipGroup retention = view.findViewById(R.id.statistics_retention);
        for (int index = 0; index < retention.getChildCount(); index++) {
            View chip = retention.getChildAt(index);
            if (chip instanceof Chip value && statistics.retention().equals(value.getTag())) {
                retention.check(value.getId());
            }
        }
        applyingState = false;

        boolean trend = section == Section.TREND;
        trendSection.setVisibility(trend ? View.VISIBLE : View.GONE);
        distributionSection.setVisibility(trend ? View.GONE : View.VISIBLE);
        if (trend) {
            // 画到最早那条记录为止：把 30 天固定死，会给一个用了三天的人画二十七天的零，
            // 那条线读起来像是刚刚才开始用，而不是刚刚才装上。一周是下限，两个点不成其为趋势。
            int span = statistics.recordedSpan(day);
            int days = span <= 0 ? DEFAULT_TREND_DAYS
                : Math.min(DEFAULT_TREND_DAYS, Math.max(MIN_TREND_DAYS, span));
            int[] series = statistics.trend(day, days);
            ((TextView) view.findViewById(R.id.statistics_trend_title))
                .setText("每日趋势 · 近 " + days + " 天");
            ((TrendChart) view.findViewById(R.id.statistics_trend)).setDaily(series);
            ((HeatmapView) view.findViewById(R.id.statistics_heatmap))
                .setDaily(statistics.trend(day, DEFAULT_TREND_DAYS * 4));
            return;
        }
        List<TypingStatisticsModel.Slice> slices = statistics.slices(section, null);
        ((TextView) view.findViewById(R.id.statistics_distribution_title))
            .setText(section.heading());
        ((DistributionView) view.findViewById(R.id.statistics_distribution)).setSlices(slices);
        ((TextView) view.findViewById(R.id.statistics_distribution_note)).setText(note(section));
    }

    private static String note(Section section) {
        return switch (section) {
            case KIND -> "按上屏字符本身分类。组合表情算一个字符，历史记录里没有分类的计入「历史未分类」。";
            case MODE -> "按提交时使用的键盘模式统计，不推测文本语言；中文模式下输入的数字仍计入中文模式。AI 润色和语音输入单独按来源统计。";
            case SCHEME -> "拼音方案统计其上屏字符数，不计未上屏的拼音按键。旧版本总数保留为历史未分类，新输入开始记录细分。";
            case TREND -> "";
        };
    }

    private static Map<String, String> retentions() {
        java.util.LinkedHashMap<String, String> values = new java.util.LinkedHashMap<>();
        values.put("forever", "一直保留");
        values.put("365d", "一年");
        values.put("180d", "半年");
        values.put("90d", "90 天");
        values.put("30d", "30 天");
        return java.util.Collections.unmodifiableMap(values);
    }
}
