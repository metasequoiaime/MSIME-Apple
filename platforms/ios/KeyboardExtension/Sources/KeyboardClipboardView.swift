import UIKit

final class KeyboardClipboardView: UIView, UITableViewDataSource, UITableViewDelegate {
  private let store: ClipboardHistoryStore
  private var items: [ClipboardHistoryItem] = []
  private let table = UITableView(frame: .zero, style: .plain)
  private let status = UILabel()
  private let onInsert: (String) -> Void
  private var confirmingClear = false

  init(hasFullAccess: Bool, store: ClipboardHistoryStore = ClipboardHistoryStore(),
       onInsert: @escaping (String) -> Void, onClose: @escaping () -> Void) {
    self.store = store
    self.onInsert = onInsert
    super.init(frame: .zero)
    accessibilityIdentifier = "keyboardClipboardHistory"
    backgroundColor = .systemBackground
    let title = UILabel()
    title.text = "剪贴板历史"
    title.font = .boldSystemFont(ofSize: 16)
    let close = UIButton(type: .system)
    close.setTitle("返回", for: .normal)
    close.addAction(UIAction { _ in onClose() }, for: .primaryActionTriggered)
    let clear = UIButton(type: .system)
    clear.setTitle("清空", for: .normal)
    clear.accessibilityIdentifier = "clearClipboardHistory"
    clear.addAction(UIAction { [weak self, weak clear] _ in
      guard let self else { return }
      if !confirmingClear {
        confirmingClear = true
        clear?.setTitle("确认清空", for: .normal)
        status.text = "再次点按清空将删除全部历史，包括固定项。"
      } else {
        perform { try store.save([]) }
        confirmingClear = false
        clear?.setTitle("清空", for: .normal)
      }
    }, for: .primaryActionTriggered)
    let header = UIStackView(arrangedSubviews: [title, clear, close])
    header.spacing = 8
    let capture = UIButton(type: .system)
    var config = UIButton.Configuration.tinted()
    config.title = "保存当前剪贴板"
    config.image = UIImage(systemName: "doc.on.clipboard")
    config.imagePadding = 8
    capture.configuration = config
    capture.accessibilityIdentifier = "captureClipboard"
    capture.isEnabled = hasFullAccess
    clear.isEnabled = hasFullAccess
    capture.addAction(UIAction { [weak self] _ in
      guard let self else { return }
      perform { try store.add(UIPasteboard.general.string ?? "") }
    }, for: .primaryActionTriggered)
    status.font = .systemFont(ofSize: 12)
    status.textColor = .secondaryLabel
    status.numberOfLines = 2
    table.dataSource = self
    table.delegate = self
    table.rowHeight = 68
    table.accessibilityIdentifier = "clipboardHistoryList"
    table.keyboardDismissMode = .none
    for child in [header, capture, status, table] {
      child.translatesAutoresizingMaskIntoConstraints = false
      addSubview(child)
    }
    NSLayoutConstraint.activate([
      header.topAnchor.constraint(equalTo: topAnchor), header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12), header.heightAnchor.constraint(equalToConstant: 44),
      close.widthAnchor.constraint(equalToConstant: 44), clear.widthAnchor.constraint(equalToConstant: 76),
      capture.topAnchor.constraint(equalTo: header.bottomAnchor), capture.leadingAnchor.constraint(equalTo: header.leadingAnchor),
      capture.trailingAnchor.constraint(equalTo: header.trailingAnchor), capture.heightAnchor.constraint(equalToConstant: 44),
      status.topAnchor.constraint(equalTo: capture.bottomAnchor, constant: 4), status.leadingAnchor.constraint(equalTo: header.leadingAnchor),
      status.trailingAnchor.constraint(equalTo: header.trailingAnchor), status.heightAnchor.constraint(equalToConstant: 34),
      table.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 4), table.leadingAnchor.constraint(equalTo: leadingAnchor),
      table.trailingAnchor.constraint(equalTo: trailingAnchor), table.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])
    if hasFullAccess { reload() }
    else { status.text = "请在系统键盘设置中开启「允许完全访问」，再使用剪贴板历史。" }
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  private func reload() {
    do {
      items = try store.load()
      status.text = items.isEmpty ? "暂无历史。保存后点按插入；记录仅保存在本机。" : "\(items.count)/50 条 · 点按插入 · 右侧菜单可固定或删除"
      table.reloadData()
    } catch { status.text = error.localizedDescription }
  }
  private func perform(_ action: () throws -> Void) {
    do { try action(); reload() }
    catch { status.text = error.localizedDescription }
  }
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }
  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
    let item = items[indexPath.row]
    cell.textLabel?.text = item.text
    cell.textLabel?.numberOfLines = 2
    cell.textLabel?.font = .systemFont(ofSize: 15)
    cell.detailTextLabel?.text = (item.pinned ? "已固定 · " : "") + item.date.formatted(date: .abbreviated, time: .shortened)
    let menu = UIButton(type: .system)
    menu.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
    menu.setImage(UIImage(systemName: item.pinned ? "pin.fill" : "ellipsis"), for: .normal)
    menu.accessibilityLabel = "管理记录"
    menu.showsMenuAsPrimaryAction = true
    menu.menu = UIMenu(children: [
      UIAction(title: item.pinned ? "取消固定" : "固定", image: UIImage(systemName: "pin")) { [weak self] _ in
        self?.change(item.id, delete: false)
      },
      UIAction(title: "删除", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
        self?.change(item.id, delete: true)
      }
    ])
    cell.accessoryView = menu
    return cell
  }
  private func change(_ id: UUID, delete: Bool) {
    perform {
      var latest = try store.load()
      if delete { latest.removeAll { $0.id == id } }
      else if let index = latest.firstIndex(where: { $0.id == id }) { latest[index].pinned.toggle() }
      try store.save(latest)
    }
  }
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    onInsert(items[indexPath.row].text)
  }
}
