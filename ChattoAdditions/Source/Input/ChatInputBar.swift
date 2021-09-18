/*
 The MIT License (MIT)

 Copyright (c) 2015-present Badoo Trading Limited.

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
*/

import UIKit

public protocol ChatInputBarDelegate: AnyObject {
    func inputBarShouldBeginTextEditing(_ inputBar: ChatInputBar) -> Bool
    func inputBarDidBeginEditing(_ inputBar: ChatInputBar)
    func inputBarDidEndEditing(_ inputBar: ChatInputBar)
    func inputBarDidChangeText(_ inputBar: ChatInputBar)
    func inputBarSendButtonPressed(_ inputBar: ChatInputBar)
    func inputBar(_ inputBar: ChatInputBar, shouldFocusOnItem item: ChatInputItemProtocol) -> Bool
    func inputBar(_ inputBar: ChatInputBar, didLoseFocusOnItem item: ChatInputItemProtocol)
    func inputBar(_ inputBar: ChatInputBar, didReceiveFocusOnItem item: ChatInputItemProtocol)
    func inputBarDidShowPlaceholder(_ inputBar: ChatInputBar)
    func inputBarDidHidePlaceholder(_ inputBar: ChatInputBar)
}

@objc open class ChatInputBar: ReusableXibView {

    public var pasteActionInterceptor: PasteActionInterceptor? {
        get { return textView.pasteActionInterceptor }
        set { textView.pasteActionInterceptor = newValue }
    }

    public weak var delegate: ChatInputBarDelegate?
    public weak var presenter: ChatInputBarPresenter?

    public var shouldEnableSendButton = { (inputBar: ChatInputBar) -> Bool in
        !inputBar.textView.text.isEmpty
    }

    public var inputTextView: UITextView? {
        textView
    }

    @IBOutlet var scrollView: HorizontalStackScrollView!
    @IBOutlet var textView: ExpandableTextView!
    @IBOutlet var sendButton: UIButton!
    @IBOutlet var topBarView: UIView!
    @IBOutlet var topBarViewHeightLayoutConstraint: NSLayoutConstraint!
    @IBOutlet var tabBarContainerHeightConstraint: NSLayoutConstraint!

    public func addSubviewToTopBarView(_ subview: UIView) {
        subview.translatesAutoresizingMaskIntoConstraints = false
        topBarView.addSubview(subview)
        NSLayoutConstraint.activate([
            subview.leadingAnchor.constraint(equalTo: topBarView.leadingAnchor),
            subview.topAnchor.constraint(equalTo: topBarView.topAnchor),
            subview.trailingAnchor.constraint(equalTo: topBarView.trailingAnchor),
            subview.bottomAnchor.constraint(equalTo: topBarView.bottomAnchor)
        ])
    }
    
    class open func loadNib() -> ChatInputBar {
        let view = Bundle.resources.loadNibNamed(nibName(), owner: nil, options: nil)!.first as! ChatInputBar
        view.frame = .zero
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    override class func nibName() -> String {
        String(describing: self)
    }

    open override func awakeFromNib() {
        super.awakeFromNib()
        topBarViewHeightLayoutConstraint.constant = 32
        textView.scrollsToTop = false
        textView.delegate = self
        textView.placeholderDelegate = self
        scrollView.scrollsToTop = false
        sendButton.isEnabled = false
        
        backgroundColor = .clear //UIColor.bma_color(rgb: 0x3A4B53)
        
        textView.textColor = .white
        textView.backgroundColor = UIColor.bma_color(rgb: 0x3A4B53)
    }

    open override func updateConstraints() {
//        if self.showsTextView {
//            NSLayoutConstraint.activate(self.constraintsForVisibleTextView)
//            NSLayoutConstraint.deactivate(self.constraintsForHiddenTextView)
//        } else {
//            NSLayoutConstraint.deactivate(self.constraintsForVisibleTextView)
//            NSLayoutConstraint.activate(self.constraintsForHiddenTextView)
//        }
//
//        if self.showsSendButton {
//            NSLayoutConstraint.deactivate(self.constraintsForHiddenSendButton)
//            NSLayoutConstraint.activate(self.constraintsForVisibleSendButton)
//        } else {
//            NSLayoutConstraint.deactivate(self.constraintsForVisibleSendButton)
//            NSLayoutConstraint.activate(self.constraintsForHiddenSendButton)
//        }
        
        super.updateConstraints()
    }

    open var showsTextView: Bool = true {
        didSet {
            self.setNeedsUpdateConstraints()
            self.setNeedsLayout()
            self.updateIntrinsicContentSizeAnimated()
        }
    }

    open var showsSendButton: Bool = true {
        didSet {
            self.setNeedsUpdateConstraints()
            self.setNeedsLayout()
            self.updateIntrinsicContentSizeAnimated()
        }
    }

    public var maxCharactersCount: UInt? // nil -> unlimited

    private func updateIntrinsicContentSizeAnimated() {
        let options: UIView.AnimationOptions = [.beginFromCurrentState, .allowUserInteraction]
        UIView.animate(withDuration: 0.25, delay: .zero, options: options) {
            self.invalidateIntrinsicContentSize()
            self.layoutIfNeeded()
        }
    }

    open override func layoutSubviews() {
        // Interface rotation or size class changes will reset constraints as defined in
        // interface builder -> constraintsForVisibleTextView will be activated
        updateConstraints()
        super.layoutSubviews()
    }

    var inputItems = [ChatInputItemProtocol]() {
        didSet {
            let inputItemViews = inputItems.map { item -> ChatInputItemView in
                let inputItemView = ChatInputItemView()
                inputItemView.inputItem = item
                inputItemView.delegate = self
                return inputItemView
            }
            scrollView.addArrangedViews(inputItemViews)
        }
    }

    open func becomeFirstResponderWithInputView(_ inputView: UIView?) {
        textView.inputView = inputView
        if textView.isFirstResponder {
            textView.reloadInputViews()
        } else {
            textView.becomeFirstResponder()
        }
    }

    public var inputText: String {
        get {
            return textView.text
        }
        set {
            textView.text = newValue
            updateSendButton()
        }
    }

    public var inputSelectedRange: NSRange {
        get { return textView.selectedRange }
        set { textView.selectedRange = newValue }
    }

    public var placeholderText: String {
        get { return textView.placeholderText }
        set { textView.placeholderText = newValue }
    }

    fileprivate func updateSendButton() {
        sendButton.isEnabled = shouldEnableSendButton(self)
    }

    @IBAction func buttonTapped(_ sender: AnyObject) {
        if #available(iOS 10.0, *) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        
        presenter?.onSendButtonPressed()
        delegate?.inputBarSendButtonPressed(self)
    }

    public func setTextViewPlaceholderAccessibilityIdentifer(_ accessibilityIdentifer: String) {
        textView.setTextPlaceholderAccessibilityIdentifier(accessibilityIdentifer)
    }
}

// MARK: - ChatInputItemViewDelegate

extension ChatInputBar: ChatInputItemViewDelegate {
    func inputItemViewTapped(_ view: ChatInputItemView) {
        focusOnInputItem(view.inputItem)
    }

    public func focusOnInputItem(_ inputItem: ChatInputItemProtocol) {
        let shouldFocus = delegate?.inputBar(self, shouldFocusOnItem: inputItem) ?? true
        guard shouldFocus else { return }

        let previousFocusedItem = presenter?.focusedItem
        presenter?.onDidReceiveFocusOnItem(inputItem)

        if let previousFocusedItem = previousFocusedItem {
            delegate?.inputBar(self, didLoseFocusOnItem: previousFocusedItem)
        }
        delegate?.inputBar(self, didReceiveFocusOnItem: inputItem)
    }
}

// MARK: - ChatInputBarAppearance

extension ChatInputBar {
    public func setAppearance(_ appearance: ChatInputBarAppearance) {
        topBarView.backgroundColor = appearance.textInputAppearance.backgroundColor
        topBarView.layer.borderColor = appearance.textInputAppearance.borderColor.cgColor
        topBarView.layer.borderWidth = appearance.sendButtonAppearance.borderWidth
        
        textView.font = appearance.textInputAppearance.font
        textView.textColor = appearance.textInputAppearance.textColor
        textView.tintColor = appearance.textInputAppearance.tintColor
        textView.backgroundColor = appearance.textInputAppearance.backgroundColor
        textView.keyboardAppearance = .dark
        textView.keyboardDismissMode = .interactive
        
        textView.textContainerInset = appearance.textInputAppearance.textInsets
        textView.setTextPlaceholderFont(appearance.textInputAppearance.placeholderFont)
        textView.setTextPlaceholderColor(appearance.textInputAppearance.placeholderColor)
        textView.placeholderText = appearance.textInputAppearance.placeholderText
        
        textView.layer.borderColor = appearance.textInputAppearance.borderColor.cgColor
        textView.layer.borderWidth = appearance.textInputAppearance.borderWidth
        textView.accessibilityIdentifier = appearance.textInputAppearance.accessibilityIdentifier
        
        tabBarInterItemSpacing = appearance.tabBarAppearance.interItemSpacing
        
        tabBarContentInsets = appearance.tabBarAppearance.contentInsets
        
        sendButton.backgroundColor = appearance.sendButtonAppearance.backgroundColor
        sendButton.tintColor = .white
        sendButton.imageView?.contentMode = .scaleAspectFit
        if #available(iOS 13.0, *) {
            let image = UIImage(systemName: "paperplane.fill")?.rotate(radians: .pi * 0.25)
            sendButton.setImage(image, for: .normal)
        } else {
            // Fallback on earlier versions
        }
        sendButton.contentEdgeInsets = appearance.sendButtonAppearance.insets
        sendButton.setTitle(appearance.sendButtonAppearance.title, for: .normal)
        appearance.sendButtonAppearance.titleColors.forEach { state, color in
            self.sendButton.setTitleColor(color, for: state.controlState)
        }
        sendButton.titleLabel?.font = appearance.sendButtonAppearance.font
        sendButton.accessibilityIdentifier = appearance.sendButtonAppearance.accessibilityIdentifier
        
        sendButton.layer.borderWidth = appearance.sendButtonAppearance.borderWidth
        sendButton.layer.borderColor = appearance.sendButtonAppearance.borderColor.cgColor
        
        tabBarContainerHeightConstraint.constant = appearance.tabBarAppearance.height
    }
}

extension UIImage {
    func rotate(radians: Float) -> UIImage? {
        var newSize = CGRect(origin: CGPoint.zero, size: size).applying(CGAffineTransform(rotationAngle: CGFloat(radians))).size
        // Trim off the extremely small float value to prevent core graphics from rounding it up
        newSize.width = floor(newSize.width)
        newSize.height = floor(newSize.height)

        UIGraphicsBeginImageContextWithOptions(newSize, false, scale)
        let context = UIGraphicsGetCurrentContext()!
        // Move origin to middle
        context.translateBy(x: newSize.width / 2 - 2.5, y: newSize.height / 2)
        // Rotate around middle
        context.rotate(by: CGFloat(radians))
        // Draw the image at its center
        draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()?.withRenderingMode(.alwaysTemplate)
        UIGraphicsEndImageContext()

        return newImage
    }
}

extension ChatInputBar { // Tab bar
    public var tabBarInterItemSpacing: CGFloat {
        get { return scrollView.interItemSpacing }
        set { scrollView.interItemSpacing = newValue }
    }

    public var tabBarContentInsets: UIEdgeInsets {
        get { return scrollView.contentInset }
        set { scrollView.contentInset = newValue }
    }
}

// MARK: UITextViewDelegate

extension ChatInputBar: UITextViewDelegate {
    public func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        delegate?.inputBarShouldBeginTextEditing(self) ?? true
    }

    public func textViewDidEndEditing(_ textView: UITextView) {
        presenter?.onDidEndEditing()
        delegate?.inputBarDidEndEditing(self)
    }

    public func textViewDidBeginEditing(_ textView: UITextView) {
        presenter?.onDidBeginEditing()
        delegate?.inputBarDidBeginEditing(self)
    }

    public func textViewDidChange(_ textView: UITextView) {
        updateSendButton()
        delegate?.inputBarDidChangeText(self)
    }

    open func textView(_ textView: UITextView, shouldChangeTextIn nsRange: NSRange, replacementText text: String) -> Bool {
        guard let maxCharactersCount = maxCharactersCount else { return true }
        let currentText: NSString = textView.text as NSString
        let currentCount = currentText.length
        let rangeLength = nsRange.length
        let nextCount = currentCount - rangeLength + (text as NSString).length
        return UInt(nextCount) <= maxCharactersCount
    }
}

// MARK: ExpandableTextViewPlaceholderDelegate

extension ChatInputBar: ExpandableTextViewPlaceholderDelegate {
    public func expandableTextViewDidShowPlaceholder(_ textView: ExpandableTextView) {
        delegate?.inputBarDidShowPlaceholder(self)
    }

    public func expandableTextViewDidHidePlaceholder(_ textView: ExpandableTextView) {
        delegate?.inputBarDidHidePlaceholder(self)
    }
}
