import UIKit

/// iOS shows a paste notice whenever a keyboard reads what is on the pasteboard, so history is never recorded in the background the way the desktop records it. The change count and `hasStrings` can be read without that notice: they tell the panel that text has been copied since the last save, and the user's tap does the actual read.
enum ClipboardCapturePrompt {
  static let key = "clipboard.lastCapturedChangeCount"

  static func hasNewCopy(changeCount: Int, hasStrings: Bool, defaults: UserDefaults = .standard) -> Bool {
    hasStrings && defaults.object(forKey: key) as? Int != changeCount
  }

  static func markCaptured(changeCount: Int, defaults: UserDefaults = .standard) {
    defaults.set(changeCount, forKey: key)
  }
}

final class KeyboardClipboardView: UIView, UITableViewDataSource, UITableViewDelegate {
  private let store: ClipboardHistoryStore
  private var items: [ClipboardHistoryItem] = []
  private let table = UITableView(frame: .zero, style: .plain)
  private let status = UILabel()
  private let onInsert: (String) -> Void
  private var confirmingClear = false
  /// Windows' 搜索剪贴板 box. A keyboard cannot type into a text field of its own, so the panel brings a letter and digit pad; `nil` while not searching.
  private(set) var searchQuery: String?
  /// What the table shows: the whole history, or the matches while searching.
  private var shown: [ClipboardHistoryItem] { ClipboardHistoryItem.matching(items, query: searchQuery ?? "") }
  private let title = UILabel()
  private let capture = UIButton(type: .system)
  private let letterPad = UIStackView()
  private let empty = UILabel()
  private lazy var captureHeight = capture.heightAnchor.constraint(equalToConstant: 44)
  private lazy var statusHeight = status.heightAnchor.constraint(equalToConstant: 34)
  private lazy var tableAboveBottom = table.bottomAnchor.constraint(equalTo: bottomAnchor)
  private lazy var tableAbovePad = table.bottomAnchor.constraint(equalTo: letterPad.topAnchor, constant: -4)
  static let searchLimit = 32

  init(hasFullAccess: Bool, store: ClipboardHistoryStore = ClipboardHistoryStore(),
       onInsert: @escaping (String) -> Void, onClose: @escaping () -> Void) {
    self.store = store
    self.onInsert = onInsert
    super.init(frame: .zero)
    accessibilityIdentifier = "keyboardClipboardHistory"
    backgroundColor = .systemBackground
    title.text = "剪贴板历史"
    title.font = .boldSystemFont(ofSize: 16)
    title.lineBreakMode = .byTruncatingHead
    title.accessibilityIdentifier = "clipboardTitle"
    let search = UIButton(type: .system)
    search.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)
    search.accessibilityLabel = "搜索剪贴板"
    search.accessibilityIdentifier = "clipboardSearch"
    search.isEnabled = hasFullAccess
    search.addAction(UIAction { [weak self] _ in
      guard let self else { return }
      if searchQuery == nil { beginSearch() } else { endSearch() }
    }, for: .primaryActionTriggered)
    let close = UIButton(type: .system)
    close.setTitle("返回", for: .normal)
    // Back leaves the search before it leaves the panel, as in the symbol panel.
    close.addAction(UIAction { [weak self] _ in
      if self?.searchQuery != nil { self?.endSearch() } else { onClose() }
    }, for: .primaryActionTriggered)
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
        perform { try store.clear() }
        confirmingClear = false
        clear?.setTitle("清空", for: .normal)
      }
    }, for: .primaryActionTriggered)
    let header = UIStackView(arrangedSubviews: [title, search, clear, close])
    header.spacing = 8
    title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let pasteboard = UIPasteboard.general
    let newCopy = hasFullAccess && ClipboardCapturePrompt.hasNewCopy(
      changeCount: pasteboard.changeCount, hasStrings: pasteboard.hasStrings)
    var config = newCopy ? UIButton.Configuration.filled() : UIButton.Configuration.tinted()
    config.title = newCopy ? "保存新复制的内容" : "保存当前剪贴板"
    config.image = UIImage(systemName: "doc.on.clipboard")
    config.imagePadding = 8
    capture.configuration = config
    capture.accessibilityIdentifier = "captureClipboard"
    capture.isEnabled = hasFullAccess
    clear.isEnabled = hasFullAccess
    capture.addAction(UIAction { [weak self] _ in
      guard let self else { return }
      let changeCount = pasteboard.changeCount
      var captured = false
      perform {
        try store.add(pasteboard.string ?? "")
        ClipboardCapturePrompt.markCaptured(changeCount: changeCount)
        captured = true
      }
      guard captured else { return }
      var saved = UIButton.Configuration.tinted()
      saved.title = "保存当前剪贴板"
      saved.image = UIImage(systemName: "doc.on.clipboard")
      saved.imagePadding = 8
      capture.configuration = saved
    }, for: .primaryActionTriggered)
    status.font = .systemFont(ofSize: 12)
    status.textColor = .secondaryLabel
    status.numberOfLines = 2
    table.dataSource = self
    table.delegate = self
    table.rowHeight = 68
    table.accessibilityIdentifier = "clipboardHistoryList"
    table.keyboardDismissMode = .none
    empty.text = "没有匹配的记录"
    empty.textAlignment = .center
    empty.textColor = .secondaryLabel
    empty.font = .systemFont(ofSize: 14)
    buildLetterPad()
    letterPad.isHidden = true
    for child in [header, capture, status, table, letterPad] {
      child.translatesAutoresizingMaskIntoConstraints = false
      addSubview(child)
    }
    NSLayoutConstraint.activate([
      header.topAnchor.constraint(equalTo: topAnchor), header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12), header.heightAnchor.constraint(equalToConstant: 44),
      close.widthAnchor.constraint(equalToConstant: 44), clear.widthAnchor.constraint(equalToConstant: 76),
      search.widthAnchor.constraint(equalToConstant: 36),
      capture.topAnchor.constraint(equalTo: header.bottomAnchor), capture.leadingAnchor.constraint(equalTo: header.leadingAnchor),
      capture.trailingAnchor.constraint(equalTo: header.trailingAnchor), captureHeight,
      status.topAnchor.constraint(equalTo: capture.bottomAnchor, constant: 4), status.leadingAnchor.constraint(equalTo: header.leadingAnchor),
      status.trailingAnchor.constraint(equalTo: header.trailingAnchor), statusHeight,
      table.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 4), table.leadingAnchor.constraint(equalTo: leadingAnchor),
      table.trailingAnchor.constraint(equalTo: trailingAnchor), tableAboveBottom,
      letterPad.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
      letterPad.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
      letterPad.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
      letterPad.heightAnchor.constraint(equalToConstant: 4 * 30 + 3 * 4),
    ])
    if hasFullAccess { reload() }
    else { status.text = "请在系统键盘设置中开启「允许完全访问」，再使用剪贴板历史。" }
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  private func reload() {
    do {
      items = try store.load()
      status.text = items.isEmpty ? "暂无历史。保存后点按插入；记录仅保存在本机。" : "\(items.count)/50 条 · 点按插入 · 右侧菜单可固定或删除"
      if searchQuery != nil { showSearch() } else { table.reloadData() }
    } catch { status.text = error.localizedDescription }
  }
  /// Open the search with an empty query. The capture button and the status line fold away, since a phone-height panel with a pad under it has room for the rows and little else, and the title carries the query.
  func beginSearch() {
    guard searchQuery == nil else { return }
    confirmingClear = false
    searchQuery = ""
    captureHeight.constant = 0
    capture.isHidden = true
    statusHeight.constant = 0
    status.isHidden = true
    letterPad.isHidden = false
    tableAboveBottom.isActive = false
    tableAbovePad.isActive = true
    setNeedsLayout()
    showSearch()
  }

  func endSearch() {
    guard searchQuery != nil else { return }
    searchQuery = nil
    captureHeight.constant = 44
    capture.isHidden = false
    statusHeight.constant = 34
    status.isHidden = false
    letterPad.isHidden = true
    tableAbovePad.isActive = false
    tableAboveBottom.isActive = true
    setNeedsLayout()
    title.text = "剪贴板历史"
    table.backgroundView = nil
    table.reloadData()
  }

  func typeSearch(_ character: String) {
    guard let searchQuery, searchQuery.count < Self.searchLimit else { return }
    self.searchQuery = searchQuery + character
    showSearch()
  }

  func deleteSearchCharacter() {
    guard let searchQuery, !searchQuery.isEmpty else { return }
    self.searchQuery = String(searchQuery.dropLast())
    showSearch()
  }

  private func showSearch() {
    guard let query = searchQuery else { return }
    title.text = query.isEmpty ? "搜索剪贴板" : "搜索：\(query)"
    table.backgroundView = !query.isEmpty && shown.isEmpty ? empty : nil
    table.reloadData()
  }

  /// Letters and digits: what is searchable in a clipboard without a Chinese composition — links, codes, numbers and English. The digit row sits on top as on the desktop keyboard.
  private func buildLetterPad() {
    letterPad.axis = .vertical
    letterPad.spacing = 4
    letterPad.distribution = .fillEqually
    letterPad.accessibilityIdentifier = "clipboardSearchPad"
    for (index, row) in ["1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm"].enumerated() {
      let line = UIStackView()
      line.axis = .horizontal
      line.spacing = 4
      line.distribution = .fillEqually
      for character in row {
        line.addArrangedSubview(padKey(title: String(character), symbol: nil, identifier: "clipboardSearchKey-\(character)") { [weak self] in
          self?.typeSearch(String(character))
        })
      }
      if index == 3 {
        let delete = padKey(title: nil, symbol: "delete.left", identifier: "clipboardSearchDelete") { [weak self] in
          self?.deleteSearchCharacter()
        }
        delete.accessibilityLabel = "删除搜索字符"
        line.addArrangedSubview(delete)
      }
      letterPad.addArrangedSubview(line)
    }
  }

  private func padKey(title: String?, symbol: String?, identifier: String, action: @escaping () -> Void) -> UIButton {
    let key = UIButton(type: .system)
    key.setTitle(title, for: .normal)
    if let symbol { key.setImage(UIImage(systemName: symbol), for: .normal) }
    key.setTitleColor(.label, for: .normal)
    key.tintColor = .label
    key.titleLabel?.font = .systemFont(ofSize: 16)
    key.backgroundColor = .secondarySystemBackground
    key.layer.cornerRadius = 5
    key.accessibilityIdentifier = identifier
    key.addAction(UIAction { _ in action() }, for: .primaryActionTriggered)
    return key
  }

  private func perform(_ action: () throws -> Void) {
    do { try action(); reload() }
    catch { status.text = error.localizedDescription }
  }
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { shown.count }
  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
    let item = shown[indexPath.row]
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
        self?.change(item, delete: false)
      },
      UIAction(title: "删除", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
        self?.change(item, delete: true)
      }
    ])
    cell.accessoryView = menu
    return cell
  }
  private func change(_ item: ClipboardHistoryItem, delete: Bool) {
    perform {
      if delete { try store.remove(text: item.text) }
      else { try store.setPinned(!item.pinned, text: item.text) }
    }
  }
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    onInsert(shown[indexPath.row].text)
  }
}
