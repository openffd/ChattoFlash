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

public protocol KeyboardEventsHandling: AnyObject {
    func onKeyboardStateDidChange(_ height: CGFloat, _ status: KeyboardStatus)
}

public protocol ScrollViewEventsHandling: AnyObject {
    func onScrollViewDidScroll(_ scrollView: UIScrollView)
    func onScrollViewDidEndDragging(_ scrollView: UIScrollView, _ decelerate: Bool)
}

public protocol ReplyActionHandler: AnyObject {
    func handleReply(for: ChatItemProtocol)
}

final class DynamicCollectionViewFlowLayout: UICollectionViewFlowLayout {
    private var dynamicAnimator: UIDynamicAnimator?
    
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        if let animator = dynamicAnimator {
            return animator.items(in: rect) as? [UICollectionViewLayoutAttributes]
        }
        
        dynamicAnimator = UIDynamicAnimator(collectionViewLayout: self)
        
        guard let items = super.layoutAttributesForElements(in: rect) else { return nil }
        items.forEach {
            let attachmentBehavior = UIAttachmentBehavior(item: $0, attachedToAnchor: $0.center)
            attachmentBehavior.length = .zero
            attachmentBehavior.damping = 0.4
            attachmentBehavior.frequency = 1
            dynamicAnimator?.addBehavior(attachmentBehavior)
        }
        return items
    }
    
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        dynamicAnimator?.layoutAttributesForCell(at: indexPath)
    }
    
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let dynamicAnimator = dynamicAnimator, let scrollView = collectionView else { return false }
        let delta = newBounds.origin.y - scrollView.bounds.origin.y
        let touchLocation = scrollView.panGestureRecognizer.location(in: scrollView)
        dynamicAnimator.behaviors.forEach {
            guard let springBehavior = $0 as? UIAttachmentBehavior else { return }
            let yDistanceFromTouch = touchLocation.y - springBehavior.anchorPoint.y
            let xDistanceFromTouch = touchLocation.x - springBehavior.anchorPoint.x
            let scrollResistance = (yDistanceFromTouch + xDistanceFromTouch) / 1500
            guard let attributes = springBehavior.items.first as? UICollectionViewLayoutAttributes else { return }
            var center = attributes.center
            if delta < .zero {
                center.y += max(delta, delta * scrollResistance)
            } else {
                center.y += min(delta, delta * scrollResistance)
            }
            attributes.center = center
            dynamicAnimator.updateItem(usingCurrentState: attributes)
        }
        return false
    }
}

open class BaseChatViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate, ChatDataSourceDelegateProtocol, InputPositionControlling, ReplyIndicatorRevealerDelegate {

    open weak var keyboardEventsHandler: KeyboardEventsHandling?
    open weak var scrollViewEventsHandler: ScrollViewEventsHandling?
    open var replyActionHandler: ReplyActionHandler?
    open var replyFeedbackGenerator: ReplyFeedbackGeneratorProtocol? = BaseChatViewController.makeReplyFeedbackGenerator()

    open var layoutConfiguration: ChatLayoutConfigurationProtocol = ChatLayoutConfiguration.defaultConfiguration {
        didSet {
            adjustCollectionViewInsets(shouldUpdateContentOffset: false)
        }
    }

    public struct Constants {
        public var updatesAnimationDuration: TimeInterval = 0.33
        
        /// If not nil, will ask data source to reduce number of messages when limit is reached. @see ChatDataSourceDelegateProtocol
        public var preferredMaxMessageCount: Int? = 500
        
        /// When the above happens, will ask to adjust with this value. It may be wise for this to be smaller to reduce number of adjustments
        public var preferredMaxMessageCountAdjustment: Int = 400
        
        public var autoloadingFractionalThreshold: CGFloat = 0.05 /// Within [0, 1]
    }

    public var constants = Constants()

    public struct UpdatesConfig {
        /// Allows another performBatchUpdates to be called before completion of a previous one (not recommended). Changing this value after viewDidLoad is not supported
        public var fastUpdates = true

        /// If receiving data source updates too fast, while an update it's being processed, only the last one will be executed
        public var coalesceUpdates = true
    }

    public var updatesConfig =  UpdatesConfig()

    /// If true then confugureCollectionViewWithPresenters() will not be called in viewDidLoad() method and has to be called manually
    open var customPresentersConfigurationPoint = false

    public private(set) var collectionView: UICollectionView?
    
    public final internal(set) var chatItemCompanionCollection = ChatItemCompanionCollection(items: [])
    
    private var _chatDataSource: ChatDataSourceProtocol?
    
    public final var chatDataSource: ChatDataSourceProtocol? {
        get { return _chatDataSource }
        set { setChatDataSource(newValue, triggeringUpdateType: .normal) }
    }

    /// If set to false messages will start appearing on top and goes down
    /// If true then messages will start from bottom and goes up.
    public var placeMessagesFromBottom = false {
        didSet {
            adjustCollectionViewInsets(shouldUpdateContentOffset: false)
        }
    }

    /// If set to false user is responsible to make sure that view provided in loadView() implements BaseChatViewContollerViewProtocol.
    /// Must be set before loadView is called.
    public var substitutesMainViewAutomatically = true

    /// Custom update on setting the data source. if triggeringUpdateType is nil it won't enqueue any update (you should do it later manually)
    public final func setChatDataSource(_ dataSource: ChatDataSourceProtocol?, triggeringUpdateType updateType: UpdateType?) {
        _chatDataSource = dataSource
        _chatDataSource?.delegate = self
        if let updateType = updateType {
            enqueueModelUpdate(updateType: updateType)
        }
    }

    deinit {
        collectionView?.delegate = nil
        collectionView?.dataSource = nil
    }

    open override func loadView() { // swiftlint:disable:this prohibited_super_call
        if substitutesMainViewAutomatically {
            // http://stackoverflow.com/questions/24596031/uiviewcontroller-with-inputaccessoryview-is-not-deallocated
            view = BaseChatViewControllerView()
            view.backgroundColor = .white
        } else {
            super.loadView()
        }
    }

    override open func viewDidLoad() {
        super.viewDidLoad()
        addCollectionView()
        addInputBarContainer()
        addInputView()
        addInputContentContainer()
        setupKeyboardTracker()
        setupTapGestureRecognizer()
    }

    private func setupTapGestureRecognizer() {
        collectionView?.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(userDidTapOnCollectionView)))
    }

    public var endsEditingWhenTappingOnChatBackground = true
    
    @objc open func userDidTapOnCollectionView() {
        if endsEditingWhenTappingOnChatBackground {
            view.endEditing(true)
        }
    }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        keyboardTracker.startTracking()
    }

    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        keyboardTracker?.stopTracking()
    }

    private func addCollectionView() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: createCollectionViewLayout())
        collectionView.contentInset = layoutConfiguration.contentInsets
        collectionView.scrollIndicatorInsets = layoutConfiguration.scrollIndicatorInsets
        collectionView.alwaysBounceVertical = true
        collectionView.backgroundColor = .clear
        collectionView.keyboardDismissMode = .interactive
        collectionView.showsVerticalScrollIndicator = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.allowsSelection = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
//        collectionView.collectionViewLayout = DynamicCollectionViewFlowLayout()
        collectionView.autoresizingMask = []
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: collectionView.topAnchor),
            view.bottomAnchor.constraint(equalTo: collectionView.bottomAnchor)
        ])

        let leadingAnchor: NSLayoutXAxisAnchor
        let trailingAnchor: NSLayoutXAxisAnchor
        if #available(iOS 11.0, *) {
            leadingAnchor = view.safeAreaLayoutGuide.leadingAnchor
            trailingAnchor = view.safeAreaLayoutGuide.trailingAnchor
        } else {
            leadingAnchor = view.leadingAnchor
            trailingAnchor = view.trailingAnchor
        }
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.chatto_setContentInsetAdjustment(enabled: false, in: self)
        collectionView.chatto_setAutomaticallyAdjustsScrollIndicatorInsets(false)
        collectionView.chatto_setIsPrefetchingEnabled(false)
        self.collectionView = collectionView
        
        let cellPanGestureHandler = CellPanGestureHandler(collectionView: collectionView)
        cellPanGestureHandler.replyDelegate = self
        cellPanGestureHandler.config = cellPanGestureHandlerConfig
        self.cellPanGestureHandler = cellPanGestureHandler

        if !customPresentersConfigurationPoint {
            confugureCollectionViewWithPresenters()
        }
    }

    var unfinishedBatchUpdatesCount: Int = 0
    var onAllBatchUpdatesFinished: (() -> Void)?

    var inputContainerBottomConstraint: NSLayoutConstraint!
    
    private var mainBackgroundColor: UIColor {
        let backgroundColor: UIColor
        if #available(iOS 10.0, *) {
            backgroundColor = UIColor(displayP3Red: 48.0 / 255, green: 62.0 / 255, blue: 69.0 / 255, alpha: 1)
        } else {
            backgroundColor = UIColor(red: 48.0 / 255, green: 62.0 / 255, blue: 69.0 / 255, alpha: 1)
        }
        return backgroundColor
    }
    
    private func addInputBarContainer() {
        self.inputBarContainer = UIView(frame: CGRect.zero)
        self.inputBarContainer.autoresizingMask = UIView.AutoresizingMask()
        self.inputBarContainer.translatesAutoresizingMaskIntoConstraints = false
        
        self.inputBarContainer.backgroundColor = mainBackgroundColor
        
        self.view.addSubview(self.inputBarContainer)
        NSLayoutConstraint.activate([
            self.inputBarContainer.topAnchor.constraint(greaterThanOrEqualTo: topLayoutGuide.bottomAnchor)
        ])
        let leadingAnchor: NSLayoutXAxisAnchor
        let trailingAnchor: NSLayoutXAxisAnchor
        if #available(iOS 11.0, *) {
            leadingAnchor = view.safeAreaLayoutGuide.leadingAnchor
            trailingAnchor = view.safeAreaLayoutGuide.trailingAnchor
        } else {
            leadingAnchor = view.leadingAnchor
            trailingAnchor = view.trailingAnchor
        }
        NSLayoutConstraint.activate([
            inputBarContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            inputBarContainer.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        inputContainerBottomConstraint = view.bottomAnchor.constraint(equalTo: inputBarContainer.bottomAnchor)
        view.addConstraint(self.inputContainerBottomConstraint)
    }

    private func addInputView() {
        let inputView = createChatInputView()
        inputBarContainer.addSubview(inputView)
        NSLayoutConstraint.activate([
            self.inputBarContainer.topAnchor.constraint(equalTo: inputView.topAnchor),
            self.inputBarContainer.bottomAnchor.constraint(equalTo: inputView.bottomAnchor),
            self.inputBarContainer.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            self.inputBarContainer.trailingAnchor.constraint(equalTo: inputView.trailingAnchor)
        ])
    }

    private func addInputContentContainer() {
        inputContentContainer = UIView(frame: .zero)
        inputContentContainer.autoresizingMask = UIView.AutoresizingMask()
        inputContentContainer.translatesAutoresizingMaskIntoConstraints = false
        
        inputContentContainer.backgroundColor = mainBackgroundColor
        
        view.addSubview(inputContentContainer)
        NSLayoutConstraint.activate([
            view.bottomAnchor.constraint(equalTo: self.inputContentContainer.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: self.inputContentContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: self.inputContentContainer.trailingAnchor),
            inputContentContainer.topAnchor.constraint(equalTo: self.inputBarContainer.bottomAnchor)
        ])
    }

    private func updateInputContainerBottomBaseOffset() {
        if #available(iOS 11.0, *) {
            let offset = self.bottomLayoutGuide.length
            if self.inputContainerBottomBaseOffset != offset {
                self.inputContainerBottomBaseOffset = offset
            }
        } else {
            // If we have been pushed on nav controller and hidesBottomBarWhenPushed = true, then ignore bottomLayoutMargin
            // because it has incorrect value when we actually have a bottom bar (tabbar)
            // Also if instance of BaseChatViewController is added as childViewController to another view controller, we had to check all this stuf on parent instance instead of self
            // UPD: Fixed in iOS 11.0
            let navigatedController: UIViewController
            if let parent = self.parent, !(parent is UINavigationController || parent is UITabBarController) {
                navigatedController = parent
            } else {
                navigatedController = self
            }

            if navigatedController.hidesBottomBarWhenPushed && (navigationController?.viewControllers.count ?? 0) > 1 && navigationController?.viewControllers.last == navigatedController {
                self.inputContainerBottomBaseOffset = .zero
            } else {
                self.inputContainerBottomBaseOffset = self.bottomLayoutGuide.length
            }
        }
    }

    private var inputContainerBottomBaseOffset: CGFloat = .zero {
        didSet { self.updateInputContainerBottomConstraint() }
    }

    private var inputContainerBottomAdditionalOffset: CGFloat = .zero {
        didSet { self.updateInputContainerBottomConstraint() }
    }

    private func updateInputContainerBottomConstraint() {
        self.inputContainerBottomConstraint.constant = max(self.inputContainerBottomBaseOffset, self.inputContainerBottomAdditionalOffset)
        self.view.setNeedsLayout()
    }

    var isAdjustingInputContainer: Bool = false

    open func setupKeyboardTracker() {
        let heightBlock = { [weak self] (bottomMargin: CGFloat, keyboardStatus: KeyboardStatus) in
            guard let sSelf = self else { return }
            if let keyboardObservingDelegate = sSelf.keyboardEventsHandler {
                keyboardObservingDelegate.onKeyboardStateDidChange(bottomMargin, keyboardStatus)
            } else {
                sSelf.changeInputContentBottomMargin(bottomMargin)
            }
        }
        self.keyboardTracker = KeyboardTracker(viewController: self, inputBarContainer: self.inputBarContainer, heightBlock: heightBlock, notificationCenter: self.notificationCenter)

        (self.view as? BaseChatViewControllerViewProtocol)?.bmaInputAccessoryView = self.keyboardTracker?.trackingView
    }

    var notificationCenter = NotificationCenter.default
    var keyboardTracker: KeyboardTracker!

    public private(set) var isFirstLayout: Bool = true
    
    override open func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        self.adjustCollectionViewInsets(shouldUpdateContentOffset: true)
        self.keyboardTracker.adjustTrackingViewSizeIfNeeded()

        if self.isFirstLayout {
            self.updateQueue.start()
            self.isFirstLayout = false
        }

        self.updateInputContainerBottomBaseOffset()
    }

    public var allContentFits: Bool {
        guard let collectionView = self.collectionView else { return false }
        let inputHeightWithKeyboard = self.view.bounds.height - self.inputBarContainer.frame.minY
        let insetTop = self.topLayoutGuide.length + self.layoutConfiguration.contentInsets.top
        let insetBottom = self.layoutConfiguration.contentInsets.bottom + inputHeightWithKeyboard
        let availableHeight = collectionView.bounds.height - (insetTop + insetBottom)
        let contentSize = collectionView.collectionViewLayout.collectionViewContentSize
        return availableHeight >= contentSize.height
    }

    private var previousBoundsUsedForInsetsAdjustment: CGRect?
    
    func adjustCollectionViewInsets(shouldUpdateContentOffset: Bool) {
        guard let collectionView = collectionView else { return }
        let isInteracting = collectionView.panGestureRecognizer.numberOfTouches > 0
        let isBouncingAtTop = isInteracting && collectionView.contentOffset.y < -collectionView.contentInset.top
        if !placeMessagesFromBottom && isBouncingAtTop { return }

        let inputHeightWithKeyboard = self.view.bounds.height - self.inputBarContainer.frame.minY
        let newInsetBottom = self.layoutConfiguration.contentInsets.bottom + inputHeightWithKeyboard
        let insetBottomDiff = newInsetBottom - collectionView.contentInset.bottom
        var newInsetTop = self.topLayoutGuide.length + self.layoutConfiguration.contentInsets.top
        let contentSize = collectionView.collectionViewLayout.collectionViewContentSize

        let needToPlaceMessagesAtBottom = placeMessagesFromBottom && allContentFits
        if needToPlaceMessagesAtBottom {
            let realContentHeight = contentSize.height + newInsetTop + newInsetBottom
            newInsetTop += collectionView.bounds.height - realContentHeight
        }

        let insetTopDiff = newInsetTop - collectionView.contentInset.top
        let needToUpdateContentInset = placeMessagesFromBottom && (insetTopDiff != 0 || insetBottomDiff != 0)

        let prevContentOffsetY = collectionView.contentOffset.y

        let boundsHeightDiff: CGFloat = {
            guard shouldUpdateContentOffset, let lastUsedBounds = previousBoundsUsedForInsetsAdjustment else { return 0 }
            let diff = lastUsedBounds.height - collectionView.bounds.height
            // When collectionView is scrolled to bottom and height increases,
            // collectionView adjusts its contentOffset automatically
            let isScrolledToBottom = contentSize.height <= collectionView.bounds.maxY - collectionView.contentInset.bottom
            return isScrolledToBottom ? max(.zero, diff) : diff
        }()
        previousBoundsUsedForInsetsAdjustment = collectionView.bounds

        let newContentOffsetY: CGFloat = {
            let minOffset = -newInsetTop
            let maxOffset = contentSize.height - (collectionView.bounds.height - newInsetBottom)
            let targetOffset = prevContentOffsetY + insetBottomDiff + boundsHeightDiff
            return max(min(maxOffset, targetOffset), minOffset)
        }()

        collectionView.contentInset = {
            var currentInsets = collectionView.contentInset
            currentInsets.bottom = newInsetBottom
            currentInsets.top = newInsetTop
            return currentInsets
        }()

        collectionView.chatto_setVerticalScrollIndicatorInsets({
            var currentInsets = collectionView.scrollIndicatorInsets
            currentInsets.bottom = layoutConfiguration.scrollIndicatorInsets.bottom + inputHeightWithKeyboard
            currentInsets.top = topLayoutGuide.length + layoutConfiguration.scrollIndicatorInsets.top
            return currentInsets
        }())

        guard shouldUpdateContentOffset else { return }

        let inputIsAtBottom = view.bounds.maxY - inputBarContainer.frame.maxY <= .zero
        if isInteracting && (needToPlaceMessagesAtBottom || needToUpdateContentInset) {
            collectionView.contentOffset.y = prevContentOffsetY
        } else if allContentFits {
            collectionView.contentOffset.y = -collectionView.contentInset.top
        } else if !isInteracting || inputIsAtBottom {
            collectionView.contentOffset.y = newContentOffsetY
        }
    }

    func rectAtIndexPath(_ indexPath: IndexPath?) -> CGRect? {
        guard let collectionView = self.collectionView else { return nil }
        guard let indexPath = indexPath else { return nil }

        return collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath)?.frame
    }

    var autoLoadingEnabled: Bool = false
    var cellPanGestureHandler: CellPanGestureHandler!
    public private(set) var inputBarContainer: UIView!
    public private(set) var inputContentContainer: UIView!
    public internal(set) var presenterFactory: ChatItemPresenterFactoryProtocol!
    let presentersByCell = NSMapTable<UICollectionViewCell, AnyObject>(keyOptions: .weakMemory, valueOptions: .weakMemory)
    var visibleCells: [IndexPath: UICollectionViewCell] = [:] // @see visibleCellsAreValid(changes:)

    public internal(set) var updateQueue: SerialTaskQueueProtocol = SerialTaskQueue()

    /**
     - You can use a decorator to:
        - Provide the ChatCollectionViewLayout with margins between messages
        - Provide to your pressenters additional attributes to help them configure their cells (for instance if a bubble should show a tail)
        - You can also add new items (for instance time markers or failed cells)
    */
    public var chatItemsDecorator: ChatItemsDecoratorProtocol?

    open func createCollectionViewLayout() -> UICollectionViewLayout {
        let layout = ChatCollectionViewLayout()
        layout.delegate = self
        return layout
    }

    var layoutModel = ChatCollectionViewLayoutModel.createModel(0, itemsLayoutData: [])

    // MARK: Subclass overrides

    open func createPresenterFactory() -> ChatItemPresenterFactoryProtocol {
        // Default implementation
        return ChatItemPresenterFactory(presenterBuildersByType: self.createPresenterBuilders())
    }

    open func createPresenterBuilders() -> [ChatItemType: [ChatItemPresenterBuilderProtocol]] {
        assert(false, "Override in subclass")
        return [ChatItemType: [ChatItemPresenterBuilderProtocol]]()
    }

    open func createChatInputView() -> UIView {
        assert(false, "Override in subclass")
        return UIView()
    }

    /**
        When paginating up we need to change the scroll position as the content is pushed down.
        We take distance to top from beforeUpdate indexPath and then we make afterUpdate indexPath to appear at the same distance
    */
    open func referenceIndexPathsToRestoreScrollPositionOnUpdate(itemsBeforeUpdate: ChatItemCompanionCollection, changes: CollectionChanges) -> (beforeUpdate: IndexPath?, afterUpdate: IndexPath?) {
        let firstItemMoved = changes.movedIndexPaths.first
        return (firstItemMoved?.indexPathOld as IndexPath?, firstItemMoved?.indexPathNew as IndexPath?)
    }

    // MARK: ReplyIndicatorRevealerDelegate

    open func didPassThreshold(at: IndexPath) {
        self.replyFeedbackGenerator?.generateFeedback()
    }

    open func didFinishReplyGesture(at indexPath: IndexPath) {
        let item = self.chatItemCompanionCollection[indexPath.item].chatItem
        self.replyActionHandler?.handleReply(for: item)
    }

    open func didCancelReplyGesture(at: IndexPath) {}

    public final var cellPanGestureHandlerConfig: CellPanGestureHandlerConfig = .defaultConfig() {
        didSet {
            self.cellPanGestureHandler?.config = self.cellPanGestureHandlerConfig
        }
    }

    private static func makeReplyFeedbackGenerator() -> ReplyFeedbackGeneratorProtocol? {
        if #available(iOS 10, *) {
            return ReplyFeedbackGenerator()
        }
        return nil
    }

    // MARK: ChatDataSourceDelegateProtocol

    open func chatDataSourceDidUpdate(_ chatDataSource: ChatDataSourceProtocol, updateType: UpdateType) {
        self.enqueueModelUpdate(updateType: updateType)
    }

    open func chatDataSourceDidUpdate(_ chatDataSource: ChatDataSourceProtocol) {
        self.enqueueModelUpdate(updateType: .normal)
    }

    public var keyboardStatus: KeyboardStatus {
        return self.keyboardTracker.keyboardStatus
    }

    public var maximumInputSize: CGSize {
        return self.view.bounds.size
    }

    open var inputContentBottomMargin: CGFloat {
        return self.inputContainerBottomConstraint.constant
    }

    open func changeInputContentBottomMargin(_ newValue: CGFloat, animated: Bool = false, callback: (() -> Void)? = nil) {
        self.changeInputContentBottomMargin(newValue, animated: animated, duration: CATransaction.animationDuration(), callback: callback)
    }

    open func changeInputContentBottomMargin(_ newValue: CGFloat, animated: Bool = false, duration: CFTimeInterval, initialSpringVelocity: CGFloat = 0.0, callback: (() -> Void)? = nil) {
        guard self.inputContainerBottomConstraint.constant != newValue else { callback?(); return }
        if animated {
            self.isAdjustingInputContainer = true
            self.inputContainerBottomAdditionalOffset = newValue
            CATransaction.begin()
            UIView.animate(
                withDuration: duration,
                delay: 0.0,
                usingSpringWithDamping: 1.0,
                initialSpringVelocity: initialSpringVelocity,
                options: .curveLinear,
                animations: { self.view.layoutIfNeeded() },
                completion: { _ in })
            CATransaction.setCompletionBlock(callback) // this callback is guaranteed to be called
            CATransaction.commit()
            self.isAdjustingInputContainer = false
        } else {
            self.changeInputContentBottomMarginWithoutAnimationTo(newValue, callback: callback)
        }
    }

    open func changeInputContentBottomMargin(_ newValue: CGFloat, animated: Bool = false, duration: CFTimeInterval, timingFunction: CAMediaTimingFunction, callback: (() -> Void)? = nil) {
        guard self.inputContainerBottomConstraint.constant != newValue else { callback?(); return }
        if animated {
            self.isAdjustingInputContainer = true
            CATransaction.begin()
            CATransaction.setAnimationTimingFunction(timingFunction)
            self.inputContainerBottomAdditionalOffset = newValue
            UIView.animate(
                withDuration: duration,
                animations: { self.view.layoutIfNeeded() },
                completion: { _ in }
            )
            CATransaction.setCompletionBlock(callback) // this callback is guaranteed to be called
            CATransaction.commit()
            self.isAdjustingInputContainer = false
        } else {
            self.changeInputContentBottomMarginWithoutAnimationTo(newValue, callback: callback)
        }
    }

    private func changeInputContentBottomMarginWithoutAnimationTo(_ newValue: CGFloat, callback: (() -> Void)?) {
        self.isAdjustingInputContainer = true
        self.inputContainerBottomAdditionalOffset = newValue
        self.view.layoutIfNeeded()
        callback?()
        self.isAdjustingInputContainer = false
    }
}

extension BaseChatViewController { // Rotation
    open override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard isViewLoaded else { return }
        guard let collectionView = self.collectionView else { return }
        let shouldScrollToBottom = self.isScrolledAtBottom()
        let referenceIndexPath = collectionView.indexPathsForVisibleItems.first
        let oldRect = self.rectAtIndexPath(referenceIndexPath)
        coordinator.animate(alongsideTransition: { (_) -> Void in
            if shouldScrollToBottom {
                self.scrollToBottom(animated: false)
            } else {
                let newRect = self.rectAtIndexPath(referenceIndexPath)
                self.scrollToPreservePosition(oldRefRect: oldRect, newRefRect: newRect)
            }
        }, completion: nil)
    }
}
