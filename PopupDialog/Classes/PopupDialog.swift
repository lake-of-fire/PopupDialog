//
//  PopupDialog.swift
//
//  Copyright (c) 2016 Orderella Ltd. (http://orderella.co.uk)
//  Author - Martin Wildfeuer (http://www.mwfire.de)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation
import UIKit

@objc public protocol PopupDialogDelegate {
    @objc optional func popupDialogWillAppear(_ popupDialog: PopupDialog)
    @objc optional func popupDialogDidAppear(_ popupDialog: PopupDialog)
    @objc optional func popupDialogWillDisappear(_ popupDialog: PopupDialog)
    @objc optional func popupDialogDidDisappear(_ popupDialog: PopupDialog)
    @objc optional func popupDialogCompleted(_ popupDialog: PopupDialog)
}

/// Creates a Popup dialog similar to UIAlertController
final public class PopupDialog: UIViewController {

    // MARK: Private / Internal

    /// First init flag
    fileprivate var initialized = false
    
    /// Width for iPad displays
    fileprivate let preferredWidth: CGFloat
    
    /// The PopupDialog delegate
    weak var delegate: PopupDialogDelegate?

    /// The custom transition presentation manager
    fileprivate var presentationManager: PresentationManager!

    /// Interactor class for pan gesture dismissal
    fileprivate lazy var interactor = InteractiveTransition()

    /// Returns the controllers view
    internal var popupContainerView: PopupDialogContainerView {
        return view as! PopupDialogContainerView // swiftlint:disable:this force_cast
    }

    /// The set of buttons
    fileprivate var buttons = [PopupDialogButton]()

    /// Whether keyboard has shifted view
    internal var keyboardShown = false

    /// Keyboard height
    internal var keyboardHeight: CGFloat?

    // MARK: Public

    /// The content view of the popup dialog
    public var viewController: UIViewController

    /// Whether or not to shift view for keyboard display
    public var keyboardShiftsView = true

    // MARK: - Initializers

    /*!
     Creates a standard popup dialog with title, message and image field

     - parameter title:            The dialog title
     - parameter message:          The dialog message
     - parameter image:            The dialog image
     - parameter buttonAlignment:  The dialog button alignment
     - parameter transitionStyle:  The dialog transition style
     - parameter preferredWidth:   The preferred width for iPad screens
     - parameter tapGestureDismissal: Indicates if dialog can be dismissed via tap gesture
     - parameter panGestureDismissal: Indicates if dialog can be dismissed via pan gesture
     - parameter hideStatusBar:    Whether to hide the status bar on PopupDialog presentation
     - parameter completion:       Completion block invoked when dialog was dismissed

     - returns: Popup dialog default style
     */
    @objc public convenience init(
                title: String?,
                message: String?,
                image: UIImage? = nil,
                buttonAlignment: NSLayoutConstraint.Axis = .vertical,
                transitionStyle: PopupDialogTransitionStyle = .bounceUp,
                preferredWidth: CGFloat = 340,
                tapGestureDismissal: Bool = true,
                panGestureDismissal: Bool = true,
                hideStatusBar: Bool = false,
                statusBarStyle: UIStatusBarStyle = .default,
                delegate: PopupDialogDelegate? = nil) {

        // Create and configure the standard popup dialog view
        let viewController = PopupDialogDefaultViewController()
        viewController.titleText     = title
        viewController.messageText   = message
        viewController.image         = image
        viewController.hideStatusBar = hideStatusBar
        viewController.statusBarStyle = statusBarStyle

        // Call designated initializer
        self.init(viewController: viewController,
                  buttonAlignment: buttonAlignment,
                  transitionStyle: transitionStyle,
                  preferredWidth: preferredWidth,
                  tapGestureDismissal: tapGestureDismissal,
                  panGestureDismissal: panGestureDismissal,
                  delegate: delegate)
    }

    /*!
     Creates a popup dialog containing a custom view

     - parameter viewController:   A custom view controller to be displayed
     - parameter buttonAlignment:  The dialog button alignment
     - parameter transitionStyle:  The dialog transition style
     - parameter preferredWidth:   The preferred width for iPad screens
     - parameter tapGestureDismissal: Indicates if dialog can be dismissed via tap gesture
     - parameter panGestureDismissal: Indicates if dialog can be dismissed via pan gesture
     - parameter hideStatusBar:    Whether to hide the status bar on PopupDialog presentation
     - parameter completion:       Completion block invoked when dialog was dismissed

     - returns: Popup dialog with a custom view controller
     */
    @objc public init(
        viewController: UIViewController,
        buttonAlignment: NSLayoutConstraint.Axis = .vertical,
        transitionStyle: PopupDialogTransitionStyle = .bounceUp,
        preferredWidth: CGFloat = 340,
        tapGestureDismissal: Bool = true,
        panGestureDismissal: Bool = true,
        delegate: PopupDialogDelegate? = nil) {

        self.viewController = viewController
        self.preferredWidth = preferredWidth
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)

        // Init the presentation manager
        presentationManager = PresentationManager(transitionStyle: transitionStyle, interactor: interactor)

        // Assign the interactor view controller
        interactor.viewController = self

        // Define presentation styles
        transitioningDelegate = presentationManager
        modalPresentationStyle = .custom
        
        // StatusBar setup
        modalPresentationCapturesStatusBarAppearance = true

        // Add our custom view to the container
        addChild(viewController)
        popupContainerView.stackView.insertArrangedSubview(viewController.view, at: 0)
        popupContainerView.buttonStackView.axis = buttonAlignment
        viewController.didMove(toParent: self)

        // Allow for dialog dismissal on background tap
        if tapGestureDismissal {
            let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            tapRecognizer.cancelsTouchesInView = false
            popupContainerView.addGestureRecognizer(tapRecognizer)
        }
        // Allow for dialog dismissal on dialog pan gesture
        if panGestureDismissal {
            let panRecognizer = UIPanGestureRecognizer(target: interactor, action: #selector(InteractiveTransition.handlePan))
            panRecognizer.cancelsTouchesInView = false
            popupContainerView.stackView.addGestureRecognizer(panRecognizer)
        }
    }

    // Init with coder not implemented
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View life cycle

    /// Replaces controller view with popup view
    public override func loadView() {
        view = PopupDialogContainerView(frame: UIScreen.main.bounds, preferredWidth: preferredWidth)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        addObservers()

        guard !initialized else { return }
        appendButtons()
        initialized = true
        delegate?.popupDialogWillAppear?(self)
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        UIView.animate(withDuration: 0.15) {
            self.setNeedsStatusBarAppearanceUpdate()
        }
        delegate?.popupDialogDidAppear?(self)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        removeObservers()
        delegate?.popupDialogWillDisappear?(self)
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        delegate?.popupDialogDidDisappear?(self)
    }

    deinit {
        delegate?.popupDialogCompleted?(self)
        delegate = nil
    }

    // MARK: - Dismissal related

    @objc fileprivate func handleTap(_ sender: UITapGestureRecognizer) {

        // Make sure it's not a tap on the dialog but the background
        let point = sender.location(in: popupContainerView.stackView)
        guard !popupContainerView.stackView.point(inside: point, with: nil) else { return }
        self.dismiss(animated: true)
    }

    // MARK: - Button related

    /*!
     Appends the buttons added to the popup dialog
     to the placeholder stack view
     */
    fileprivate func appendButtons() {
        
        // Add action to buttons
        let stackView = popupContainerView.stackView
        let buttonStackView = popupContainerView.buttonStackView
        if buttons.isEmpty {
            stackView.removeArrangedSubview(popupContainerView.buttonStackView)
        }
        
        for (index, button) in buttons.enumerated() {
            button.needsLeftSeparator = buttonStackView.axis == .horizontal && index > 0
            buttonStackView.addArrangedSubview(button)
            button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
        }
    }

    /*!
     Adds a single PopupDialogButton to the Popup dialog
     - parameter button: A PopupDialogButton instance
     */
    @objc public func addButton(_ button: PopupDialogButton) {
        buttons.append(button)
    }

    /*!
     Adds an array of PopupDialogButtons to the Popup dialog
     - parameter buttons: A list of PopupDialogButton instances
     */
    @objc public func addButtons(_ buttons: [PopupDialogButton]) {
        self.buttons += buttons
    }

    /// Calls the action closure of the button instance tapped
    @objc fileprivate func buttonTapped(_ button: PopupDialogButton) {
        if button.dismissOnTap {
            self.dismiss(animated: true) {
                button.buttonAction?()
            }
        } else {
            button.buttonAction?()
        }
    }

    /*!
     Simulates a button tap for the given index
     Makes testing a breeze
     - parameter index: The index of the button to tap
     */
    public func tapButtonWithIndex(_ index: Int) {
        let button = buttons[index]
        button.buttonAction?()
    }
    
    // MARK: - Interface Orientations related
    
    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return self.viewController.supportedInterfaceOrientations
    }
    
    // MARK: - StatusBar display related
    
    public override var prefersStatusBarHidden: Bool {
        return self.viewController.prefersStatusBarHidden
    }
    
    public override var preferredStatusBarStyle: UIStatusBarStyle {
        return self.viewController.preferredStatusBarStyle
    }
    
    public override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        return self.viewController.preferredStatusBarUpdateAnimation
    }
}

// MARK: - View proxy values

extension PopupDialog {

    /// The button alignment of the alert dialog
    @objc public var buttonAlignment: NSLayoutConstraint.Axis {
        get {
            return popupContainerView.buttonStackView.axis
        }
        set {
            popupContainerView.buttonStackView .axis = newValue
            popupContainerView.pv_layoutIfNeededAnimated()
        }
    }

    /// The transition style
    @objc public var transitionStyle: PopupDialogTransitionStyle {
        get { return presentationManager.transitionStyle }
        set { presentationManager.transitionStyle = newValue }
    }
}

// MARK: - Shake

extension PopupDialog {
    
    /// Performs a shake animation on the dialog
    @objc public func shake() {
        popupContainerView.pv_shake()
    }
}

// MARK: - Show

extension PopupDialog {
    
    /// Present dialog by root view controller
    /// Ref: https://developer.apple.com/forums/thread/695932
    @objc public func show(animated: Bool = true, completion: (() -> Void)? = nil) {
        (UIApplication.shared.delegate?.window)!!.rootViewController!.present(self, animated: animated, completion: completion)
    }
}
