import UIKit

/// 键位间距与键盘高度:直接在键盘上拖。
///
/// 这一块原来是三条滑块铺满键盘区。值是实时生效的,可看不见 —— 面板把键盘整个盖住了,间距改了屏幕上一点变化都没有,只有高度因为面板自己跟着变才勉强看得出来。
///
/// 现在它是透明的:顶上一条窄工具条,底下整块交给手势,真键盘就在下面跟着变。上沿那条把手上下拖是高度;在键盘上左右拖是键距、上下拖是行间距。
final class KeyboardLayoutAdjustView: UIView {
  /// 拖多远算一格。高度一比一跟手;间距那两个范围只有三到六个点,跟手就会一碰到头。
  private static let spacingDragScale: Double = 18
  private static let barHeight: CGFloat = 52

  private enum Axis { case vertical, horizontal }

  private let onKeySpacing: (Double) -> Void
  private let onRowSpacing: (Double) -> Void
  private let onHeight: (Double) -> Void
  private var keySpacing: Double
  private var rowSpacing: Double
  private var height: Double
  private let hint = UILabel()
  private let grip = UIView()
  private var axis: Axis?
  private var base: (key: Double, row: Double, height: Double) = (0, 0, 0)

  init(keySpacing: Double, rowSpacing: Double, height: Double,
       onKeySpacing: @escaping (Double) -> Void,
       onRowSpacing: @escaping (Double) -> Void,
       onHeight: @escaping (Double) -> Void,
       onReset: @escaping () -> Void,
       onClose: @escaping () -> Void) {
    self.keySpacing = keySpacing
    self.rowSpacing = rowSpacing
    self.height = height
    self.onKeySpacing = onKeySpacing
    self.onRowSpacing = onRowSpacing
    self.onHeight = onHeight
    super.init(frame: .zero)
    accessibilityIdentifier = "keyboardLayoutPicker"
    let skin = KeyboardSkinPreference.selected
    // 整块是透明的:键盘要看得见,否则调的是什么就还是看不见。挡住触摸只是为了拖的时候不打出字。
    backgroundColor = .clear

    let bar = UIView()
    bar.backgroundColor = skin.keyBackground
    bar.layer.cornerRadius = 10

    let close = UIButton(type: .system)
    close.setTitle("完成", for: .normal)
    close.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
    close.setTitleColor(skin.accent, for: .normal)
    close.accessibilityIdentifier = "closeLayoutPicker"
    close.accessibilityLabel = "返回键盘"
    close.addAction(UIAction { _ in onClose() }, for: .primaryActionTriggered)

    let reset = UIButton(type: .system)
    reset.setTitle("恢复默认", for: .normal)
    reset.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
    reset.setTitleColor(.systemRed, for: .normal)
    reset.accessibilityIdentifier = "resetKeyboardSettings"
    reset.accessibilityHint = "把间距和高度恢复成默认值"
    reset.addAction(UIAction { _ in onReset() }, for: .primaryActionTriggered)

    hint.font = .systemFont(ofSize: 13)
    hint.textColor = skin.keyForeground.withAlphaComponent(0.75)
    hint.textAlignment = .center
    hint.adjustsFontSizeToFitWidth = true
    hint.minimumScaleFactor = 0.7
    hint.accessibilityIdentifier = "layoutAdjustHint"
    updateHint()

    // 把手压在工具条下沿,拖它就是拖键盘的上边。
    grip.backgroundColor = skin.accent.withAlphaComponent(0.45)
    grip.layer.cornerRadius = 2.5
    grip.isUserInteractionEnabled = false

    let gripTarget = UIView()
    gripTarget.backgroundColor = .clear
    gripTarget.accessibilityIdentifier = "keyboardHeightGrip"
    gripTarget.accessibilityLabel = "键盘高度"
    gripTarget.isAccessibilityElement = true
    gripTarget.accessibilityTraits = .adjustable
    gripTarget.addGestureRecognizer(
      UIPanGestureRecognizer(target: self, action: #selector(dragHeight(_:))))

    addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragSpacing(_:))))

    for item in [bar, close, reset, hint, grip, gripTarget] {
      item.translatesAutoresizingMaskIntoConstraints = false
      addSubview(item)
    }
    NSLayoutConstraint.activate([
      bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      bar.topAnchor.constraint(equalTo: topAnchor, constant: 4),
      bar.heightAnchor.constraint(equalToConstant: Self.barHeight),
      // 三个都对同一条中线。把手要占掉下沿那几点,所以这条线比工具条中心高一点,不是 centerY。
      close.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
      close.centerYAnchor.constraint(equalTo: hint.centerYAnchor),
      reset.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
      reset.centerYAnchor.constraint(equalTo: hint.centerYAnchor),
      hint.leadingAnchor.constraint(equalTo: reset.trailingAnchor, constant: 8),
      hint.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -8),
      hint.centerYAnchor.constraint(equalTo: bar.centerYAnchor, constant: -5),
      // 把手画在工具条自己的下沿里,不压到底下的快捷栏。整条工具条都能拖 —— 抓一条细横杠不如抓一整条。
      grip.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
      grip.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -6),
      grip.widthAnchor.constraint(equalToConstant: 46),
      grip.heightAnchor.constraint(equalToConstant: 5),
      gripTarget.leadingAnchor.constraint(equalTo: reset.trailingAnchor),
      gripTarget.trailingAnchor.constraint(equalTo: close.leadingAnchor),
      gripTarget.topAnchor.constraint(equalTo: bar.topAnchor),
      gripTarget.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  /// VoiceOver 走增减,手势之外还有一条路。
  override func accessibilityIncrement() { adjustHeight(by: 2) }
  override func accessibilityDecrement() { adjustHeight(by: -2) }

  private func adjustHeight(by delta: Double) {
    height = Self.clamp(height + delta, -12, 48)
    onHeight(height)
    updateHint()
  }

  @objc private func dragHeight(_ gesture: UIPanGestureRecognizer) {
    switch gesture.state {
    case .began:
      base = (keySpacing, rowSpacing, height)
    case .changed:
      // 往上拖是加高。屏幕坐标向下为正,所以取反。
      height = Self.clamp(base.height - Double(gesture.translation(in: self).y), -12, 48)
      onHeight(height)
      updateHint("键盘高度 \(height > 0 ? "+" : "")\(Int(height))")
    default:
      axis = nil
      updateHint()
    }
  }

  @objc private func dragSpacing(_ gesture: UIPanGestureRecognizer) {
    let translation = gesture.translation(in: self)
    switch gesture.state {
    case .began:
      base = (keySpacing, rowSpacing, height)
      axis = nil
    case .changed:
      // 第一下往哪边动得多,这一次就只改那一个 —— 手歪了也不会让两个参数互相抢。
      let direction = axis ?? (abs(translation.y) >= abs(translation.x) ? .vertical : .horizontal)
      axis = direction
      switch direction {
      case .vertical:
        rowSpacing = Self.clamp(base.row + Double(translation.y) / Self.spacingDragScale, 4, 10)
        onRowSpacing(rowSpacing)
        updateHint(String(format: "行间距 %.1f", rowSpacing))
      case .horizontal:
        keySpacing = Self.clamp(base.key + Double(translation.x) / Self.spacingDragScale, 3, 6)
        onKeySpacing(keySpacing)
        updateHint(String(format: "按键间距 %.1f", keySpacing))
      }
    default:
      axis = nil
      updateHint()
    }
  }

  /// 拖动时报当前值,松手回到说明。
  private func updateHint(_ value: String? = nil) {
    hint.text = value ?? "拖把手改高度，键盘上左右拖改键距、上下拖改行间距"
  }

  private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
    min(upper, max(lower, value))
  }
}
