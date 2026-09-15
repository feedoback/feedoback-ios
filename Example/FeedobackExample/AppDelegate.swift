import Feedoback
import UIKit

/// The smallest app that exercises the SDK the way a customer would: a
/// Settings-style list with a row that opens the sheet, plus the floating
/// launcher, an identify, and a screen name.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let key = ProcessInfo.processInfo.environment["FEEDOBACK_KEY"] ?? "pk_missing"
        let host = ProcessInfo.processInfo.environment["FEEDOBACK_HOST"] ?? "http://127.0.0.1:3000"

        Feedoback.shared.start(
            FeedobackConfiguration(
                projectKey: key,
                host: URL(string: host)!,
                theme: .system,
                categories: [.feedback, .bug, .idea],
                screenshots: .automatic,
                launcher: FeedobackLauncherOptions(enabled: true, style: .labelled),
                triggers: [.launcher, .shake],
                logLevel: .debug))

        Feedoback.shared.setScreen("settings", title: "Settings")

        if let id = ProcessInfo.processInfo.environment["FEEDOBACK_USER"] {
            Feedoback.shared.identify(
                FeedobackVisitor(
                    id: id,
                    email: ProcessInfo.processInfo.environment["FEEDOBACK_EMAIL"],
                    name: "Ada Lovelace",
                    userHash: ProcessInfo.processInfo.environment["FEEDOBACK_HASH"]))
        }

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UINavigationController(rootViewController: SettingsController())
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

final class SettingsController: UITableViewController {
    private let rows = [
        ("Send feedback", FeedobackCategory.feedback),
        ("Report a problem", FeedobackCategory.bug),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : rows.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Account" : "Feedback"
    }

    override func tableView(
        _ tableView: UITableView, cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()

        if indexPath.section == 0 {
            content.text = "Password"
            content.secondaryText = "Hidden from any screenshot"
            let field = UITextField(frame: CGRect(x: 0, y: 0, width: 120, height: 30))
            field.isSecureTextEntry = true
            field.text = "hunter2hunter2"
            field.textAlignment = .right
            cell.accessoryView = field
        } else {
            content.text = rows[indexPath.row].0
            cell.accessoryType = .disclosureIndicator
            cell.accessibilityIdentifier = rows[indexPath.row].0
        }

        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1 else { return }
        Feedoback.shared.present(category: rows[indexPath.row].1)
    }

    /// Shaking is a trigger a project can turn on; the app forwards it.
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard motion == .motionShake else { return }
        Feedoback.shared.handleShake()
    }

    override var canBecomeFirstResponder: Bool { true }
}
