import UIKit
import LiquidGlassTabBar

/// One tab's scrollable mock content. Knows nothing about the tab bar —
/// scroll tracking is attached externally by the host.
final class MockListViewController: UITableViewController {
    private let rows: [String]
    /// Extra bottom inset keeping the last rows clear of the floating
    /// custom bar. The native-tab-bar host passes 0 — the system bar
    /// manages its own safe-area insets.
    private let bottomInset: CGFloat

    init(rows: [String], bottomInset: CGFloat = 90) {
        self.rows = rows
        self.bottomInset = bottomInset
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.contentInset.bottom = bottomInset
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.text = rows[indexPath.row]
        cell.contentConfiguration = config
        return cell
    }
}
