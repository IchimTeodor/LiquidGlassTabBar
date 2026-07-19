import UIKit

/// One tab's scrollable mock content. Knows nothing about the tab bar —
/// scroll tracking is attached externally by the host.
final class MockListViewController: UITableViewController {
    private let rows: [String]

    init(rows: [String]) {
        self.rows = rows
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.contentInset.bottom = 90 // keep last rows clear of the bar
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
