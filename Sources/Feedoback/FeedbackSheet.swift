import Foundation

#if canImport(UIKit)
import UIKit

/// One screen: say the thing, and send it.
///
/// Native chrome on purpose — a sheet with a detent, the system's own fonts
/// and controls — because this appears inside somebody else's app and should
/// not look like a web page someone bolted on.
@MainActor
final class FeedbackSheetController: UIViewController {
    private let appearance: FeedobackAppearance
    private let categories: [FeedobackCategory]
    private let knowsTheVisitor: Bool
    private let theme: FeedobackTheme
    private let onSend: (FeedobackDraft) async -> FeedobackSendOutcome
    private let onClose: () -> Void

    private var draft: FeedobackDraft
    private var accent: UIColor { FeedobackPalette.accent(appearance.color) }

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let categoryControl = UISegmentedControl()
    private let starsRow = UIStackView()
    private let message = UITextView()
    private let placeholder = UILabel()
    private let emailField = UITextField()
    private let screenshotView = UIImageView()
    private let screenshotBox = UIStackView()
    private let sendButton = UIButton(type: .system)
    private let status = UILabel()
    private var stars: [UIButton] = []

    init(
        appearance: FeedobackAppearance,
        categories: [FeedobackCategory],
        category: FeedobackCategory,
        knowsTheVisitor: Bool,
        theme: FeedobackTheme,
        screenshot: Data?,
        onSend: @escaping (FeedobackDraft) async -> FeedobackSendOutcome,
        onClose: @escaping () -> Void
    ) {
        self.appearance = appearance
        self.categories = categories
        self.knowsTheVisitor = knowsTheVisitor
        self.theme = theme
        self.onSend = onSend
        self.onClose = onClose
        self.draft = FeedobackDraft(category: category, screenshot: screenshot)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    /// Fires for every way out — the close button, a swipe down, the dismissal
    /// after sending — which a presentation delegate does not: that one only
    /// hears about an interactive dismissal, so sending once would have left
    /// the launcher hidden for good.
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if view.window == nil { onClose() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = theme.interfaceStyle
        view.backgroundColor = .systemBackground
        title = appearance.welcome.isEmpty ? "Send feedback" : appearance.welcome

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(dismissSheet))

        buildLayout()
        updateSendButton()
    }

    // MARK: - How tall a sheet this needs

    /// The height of the form, so the sheet can stop there rather than filling
    /// a screen four controls do not need.
    ///
    /// Nothing else here can answer this: the stack lives inside a scroll
    /// view, so the view's own bounds say nothing about how tall its contents
    /// are. The 20pt above and below the stack and the room under the home
    /// indicator are added back, because the measurement is of the stack alone.
    var contentHeight: CGFloat {
        view.layoutIfNeeded()
        let available = max(view.bounds.width - 40, 0)
        let fitting = stack.systemLayoutSizeFitting(
            CGSize(width: available, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel)
        return fitting.height + 40 + view.safeAreaInsets.bottom
    }

    /// Asks the sheet to measure again, for the two things that change how
    /// tall the form is: the stars appearing with a category, and the
    /// screenshot being taken off.
    private func remeasure() {
        guard #available(iOS 16.0, *),
              let presentation = navigationController?.sheetPresentationController
        else { return }
        presentation.animateChanges { presentation.invalidateDetents() }
    }

    /// Writing takes the whole screen: the measured detent has no room for a
    /// keyboard, and a send button under one is a send button nobody finds.
    /// Dragging back down is the visitor's to do.
    private func growForKeyboard() {
        guard let presentation = navigationController?.sheetPresentationController,
              presentation.selectedDetentIdentifier != .large
        else { return }
        presentation.animateChanges { presentation.selectedDetentIdentifier = .large }
    }

    // MARK: - Layout

    private func buildLayout() {
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .interactive
        view.addSubview(scroll)

        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),

            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -20),
        ])

        // A control with one option is not a choice, so it only appears when
        // the project offers more than one thing to send.
        if categories.count > 1 {
            for (index, category) in categories.enumerated() {
                categoryControl.insertSegment(withTitle: title(for: category), at: index, animated: false)
            }
            categoryControl.selectedSegmentIndex = categories.firstIndex(of: draft.category) ?? 0
            categoryControl.selectedSegmentTintColor = accent
            categoryControl.setTitleTextAttributes(
                [.foregroundColor: FeedobackPalette.onAccent(accent)], for: .selected)
            categoryControl.addTarget(self, action: #selector(categoryChanged), for: .valueChanged)
            categoryControl.accessibilityLabel = "What this is about"
            stack.addArrangedSubview(categoryControl)
        }

        // Stars on feedback only: a bug report is not an experience to rate.
        if appearance.rating && draft.category == .feedback {
            stack.addArrangedSubview(buildStars())
        }

        stack.addArrangedSubview(buildMessage())

        if !knowsTheVisitor {
            stack.addArrangedSubview(buildEmail())
        }

        if draft.screenshot != nil {
            stack.addArrangedSubview(buildScreenshot())
        }

        status.font = .preferredFont(forTextStyle: .footnote)
        status.textColor = .secondaryLabel
        status.numberOfLines = 0
        status.isHidden = true
        status.accessibilityTraits = .updatesFrequently
        stack.addArrangedSubview(status)

        stack.addArrangedSubview(buildSendButton())
    }

    private func title(for category: FeedobackCategory) -> String {
        switch category {
        case .feedback: return "Feedback"
        case .bug: return "Problem"
        case .idea: return "Idea"
        }
    }

    private func buildStars() -> UIView {
        starsRow.axis = .horizontal
        starsRow.spacing = 8
        starsRow.isAccessibilityElement = false
        starsRow.accessibilityLabel = "Rating"

        for value in 1...5 {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: "star"), for: .normal)
            button.tintColor = .tertiaryLabel
            button.tag = value
            button.accessibilityLabel = "\(value) out of 5"
            button.addTarget(self, action: #selector(rate(_:)), for: .touchUpInside)
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
            stars.append(button)
            starsRow.addArrangedSubview(button)
        }
        starsRow.addArrangedSubview(UIView())
        return starsRow
    }

    private func buildMessage() -> UIView {
        let box = UIView()
        box.backgroundColor = .secondarySystemBackground
        box.layer.cornerRadius = 10
        box.layer.borderWidth = 1
        box.layer.borderColor = UIColor.separator.cgColor

        message.translatesAutoresizingMaskIntoConstraints = false
        message.backgroundColor = .clear
        message.font = .preferredFont(forTextStyle: .body)
        message.adjustsFontForContentSizeCategory = true
        message.delegate = self
        message.accessibilityLabel = "Your feedback"
        message.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        box.addSubview(message)

        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.text = "What could be better?"
        placeholder.font = .preferredFont(forTextStyle: .body)
        placeholder.textColor = .placeholderText
        placeholder.isAccessibilityElement = false
        box.addSubview(placeholder)

        NSLayoutConstraint.activate([
            message.topAnchor.constraint(equalTo: box.topAnchor),
            message.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 4),
            message.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -4),
            message.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            message.heightAnchor.constraint(greaterThanOrEqualToConstant: 132),

            placeholder.topAnchor.constraint(equalTo: message.topAnchor, constant: 12),
            placeholder.leadingAnchor.constraint(equalTo: message.leadingAnchor, constant: 13),
        ])
        return box
    }

    private func buildEmail() -> UIView {
        emailField.placeholder = "Your email, to hear back"
        emailField.borderStyle = .roundedRect
        emailField.keyboardType = .emailAddress
        emailField.textContentType = .emailAddress
        emailField.autocapitalizationType = .none
        emailField.autocorrectionType = .no
        emailField.font = .preferredFont(forTextStyle: .body)
        emailField.adjustsFontForContentSizeCategory = true
        emailField.accessibilityLabel = "Your email"
        emailField.heightAnchor.constraint(equalToConstant: 44).isActive = true
        emailField.addTarget(self, action: #selector(editingBegan), for: .editingDidBegin)
        return emailField
    }

    private func buildScreenshot() -> UIView {
        screenshotBox.axis = .horizontal
        screenshotBox.spacing = 12
        screenshotBox.alignment = .center

        screenshotView.contentMode = .scaleAspectFit
        screenshotView.layer.cornerRadius = 6
        screenshotView.layer.borderWidth = 1
        screenshotView.layer.borderColor = UIColor.separator.cgColor
        screenshotView.clipsToBounds = true
        screenshotView.isAccessibilityElement = true
        screenshotView.accessibilityLabel = "The screen this will be sent with"
        if let data = draft.screenshot { screenshotView.image = UIImage(data: data) }
        screenshotView.widthAnchor.constraint(equalToConstant: 44).isActive = true
        screenshotView.heightAnchor.constraint(equalToConstant: 76).isActive = true

        let label = UILabel()
        label.text = "This screen is attached"
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 0

        // The strongest privacy guarantee available, and it costs nothing:
        // nothing is sent that the visitor did not look at and keep.
        let remove = UIButton(type: .system)
        remove.setTitle("Remove", for: .normal)
        remove.tintColor = .secondaryLabel
        remove.accessibilityLabel = "Remove the screen"
        remove.addTarget(self, action: #selector(removeScreenshot), for: .touchUpInside)
        remove.setContentHuggingPriority(.required, for: .horizontal)

        screenshotBox.addArrangedSubview(screenshotView)
        screenshotBox.addArrangedSubview(label)
        screenshotBox.addArrangedSubview(remove)
        return screenshotBox
    }

    private func buildSendButton() -> UIView {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Send"
        configuration.baseBackgroundColor = accent
        configuration.baseForegroundColor = FeedobackPalette.onAccent(accent)
        configuration.cornerStyle = .medium
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 14, leading: 20, bottom: 14, trailing: 20)

        sendButton.configuration = configuration
        sendButton.addTarget(self, action: #selector(send), for: .touchUpInside)
        sendButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        return sendButton
    }

    // MARK: - Reacting

    @objc private func editingBegan() {
        growForKeyboard()
    }

    @objc private func categoryChanged() {
        let index = categoryControl.selectedSegmentIndex
        guard categories.indices.contains(index) else { return }
        draft.category = categories[index]
        placeholder.text = draft.category == .bug ? "What went wrong?" : "What could be better?"
        // Stars belong to feedback, so they go when it is no longer that.
        starsRow.isHidden = draft.category != .feedback
        if draft.category != .feedback { draft.rating = nil; paintStars() }
        remeasure()
    }

    @objc private func rate(_ sender: UIButton) {
        draft.rating = draft.rating == sender.tag ? nil : sender.tag
        paintStars()
        updateSendButton()
    }

    private func paintStars() {
        for button in stars {
            let filled = button.tag <= (draft.rating ?? 0)
            button.setImage(UIImage(systemName: filled ? "star.fill" : "star"), for: .normal)
            button.tintColor = filled ? accent : .tertiaryLabel
            button.accessibilityTraits = filled ? [.button, .selected] : .button
        }
    }

    @objc private func removeScreenshot() {
        draft.screenshot = nil
        screenshotBox.isHidden = true
        UIAccessibility.post(notification: .announcement, argument: "Screen removed")
        remeasure()
    }

    @objc private func dismissSheet() {
        presentingViewController?.dismiss(animated: true)
    }

    private func updateSendButton() {
        sendButton.isEnabled = draft.hasSomethingToSay
        sendButton.alpha = sendButton.isEnabled ? 1 : 0.5
    }

    @objc private func send() {
        guard draft.hasSomethingToSay else { return }

        draft.body = message.text ?? ""
        draft.email = emailField.text
        setBusy(true)

        Task { @MainActor in
            let outcome = await onSend(draft)
            setBusy(false)
            switch outcome {
            case .sent:
                finish("Thank you. Sent.")
            case .queued:
                // Honest rather than cheerful: it is not there yet, and the
                // visitor should not have to wonder later.
                finish("No connection. This will send itself later.")
            case .refused, .failed:
                show("That could not be sent. Try again in a moment.")
            }
        }
    }

    private func setBusy(_ busy: Bool) {
        sendButton.configuration?.showsActivityIndicator = busy
        sendButton.isEnabled = !busy && draft.hasSomethingToSay
        message.isEditable = !busy
        emailField.isEnabled = !busy
    }

    private func show(_ text: String) {
        status.text = text
        status.isHidden = false
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    private func finish(_ text: String) {
        show(text)
        // Long enough to read, short enough not to trap anyone in a sheet
        // they are done with.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            self?.presentingViewController?.dismiss(animated: true)
        }
    }
}

extension FeedbackSheetController: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        growForKeyboard()
    }

    func textViewDidChange(_ textView: UITextView) {
        placeholder.isHidden = !(textView.text ?? "").isEmpty
        draft.body = textView.text ?? ""
        updateSendButton()
    }
}
#endif
