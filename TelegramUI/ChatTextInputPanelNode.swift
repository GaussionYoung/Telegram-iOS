import Foundation
import UIKit
import Display
import AsyncDisplayKit
import Postbox
import TelegramCore
import MobileCoreServices

private let searchLayoutProgressImage = generateImage(CGSize(width: 22.0, height: 22.0), contextGenerator: { size, context in
    context.clear(CGRect(origin: CGPoint(), size: size))
    context.setStrokeColor(UIColor(rgb: 0x9099A2, alpha: 0.6).cgColor)
    
    let lineWidth: CGFloat = 2.0
    let cutoutWidth: CGFloat = 4.0
    context.setLineWidth(lineWidth)
    
    context.strokeEllipse(in: CGRect(origin: CGPoint(x: lineWidth / 2.0, y: lineWidth / 2.0), size: CGSize(width: size.width - lineWidth, height: size.height - lineWidth)))
    context.clear(CGRect(origin: CGPoint(x: (size.width - cutoutWidth) / 2.0, y: 0.0), size: CGSize(width: cutoutWidth, height: size.height / 2.0)))
})

private final class AccessoryItemIconButton: HighlightableButton {
    private let item: ChatTextInputAccessoryItem
    
    init(item: ChatTextInputAccessoryItem, theme: PresentationTheme, strings: PresentationStrings) {
        self.item = item
        
        super.init(frame: CGRect())
        
        switch item {
            case .keyboard:
                self.setImage(PresentationResourcesChat.chatInputTextFieldKeyboardImage(theme), for: [])
            case .stickers:
                self.setImage(PresentationResourcesChat.chatInputTextFieldStickersImage(theme), for: [])
            case .inputButtons:
                self.setImage(PresentationResourcesChat.chatInputTextFieldInputButtonsImage(theme), for: [])
            case let .messageAutoremoveTimeout(timeout):
                if let timeout = timeout {
                    self.setImage(nil, for: [])
                    self.titleLabel?.font = Font.regular(12.0)
                    self.setTitleColor(theme.chat.inputPanel.inputControlColor, for: [])
                    self.setTitle(shortTimeIntervalString(strings: strings, value: timeout), for: [])
                } else {
                    self.setImage(PresentationResourcesChat.chatInputTextFieldTimerImage(theme), for: [])
                    self.imageEdgeInsets = UIEdgeInsets(top: 0.0, left: 0.0, bottom: 1.0, right: 0.0)
                }
        }
    }
    
    func updateThemeAndStrings(theme: PresentationTheme, strings: PresentationStrings) {
        switch self.item {
            case .keyboard:
                self.setImage(PresentationResourcesChat.chatInputTextFieldKeyboardImage(theme), for: [])
            case .stickers:
                self.setImage(PresentationResourcesChat.chatInputTextFieldStickersImage(theme), for: [])
            case .inputButtons:
                self.setImage(PresentationResourcesChat.chatInputTextFieldInputButtonsImage(theme), for: [])
            case let .messageAutoremoveTimeout(timeout):
                if let timeout = timeout {
                    self.setImage(nil, for: [])
                    self.titleLabel?.font = Font.regular(12.0)
                    self.setTitleColor(theme.chat.inputPanel.inputControlColor, for: [])
                    self.setTitle(shortTimeIntervalString(strings: strings, value: timeout), for: [])
                } else {
                    self.setImage(PresentationResourcesChat.chatInputTextFieldTimerImage(theme), for: [])
                    self.imageEdgeInsets = UIEdgeInsets(top: 0.0, left: 0.0, bottom: 1.0, right: 0.0)
                }
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var buttonWidth: CGFloat {
        switch self.item {
            case .keyboard, .stickers, .inputButtons:
                return (self.image(for: [])?.size.width ?? 0.0) + CGFloat(8.0)
            case let .messageAutoremoveTimeout(timeout):
                return 24.0
        }
    }
}

class ChatTextInputPanelNode: ChatInputPanelNode, ASEditableTextNodeDelegate {
    var textPlaceholderNode: TextNode
    var contextPlaceholderNode: TextNode?
    let textInputContainer: ASDisplayNode
    var textInputNode: ASEditableTextNode?
    
    let textInputBackgroundView: UIImageView
    let micButton: ChatTextInputMediaRecordingButton
    let sendButton: HighlightableButton
    private var sendButtonHasApplyIcon = false
    private var animatingSendButton = false
    let attachmentButton: HighlightableButton
    let searchLayoutClearButton: HighlightableButton
    let searchLayoutProgressView: UIImageView
    var audioRecordingInfoContainerNode: ASDisplayNode?
    var audioRecordingDotNode: ASImageNode?
    var audioRecordingTimeNode: ChatTextInputAudioRecordingTimeNode?
    var audioRecordingCancelIndicator: ChatTextInputAudioRecordingCancelIndicator?
    
    private var accessoryItemButtons: [(ChatTextInputAccessoryItem, AccessoryItemIconButton)] = []
    
    private var validLayout: (CGFloat, CGFloat, CGFloat, CGFloat)?
    
    var displayAttachmentMenu: () -> Void = { }
    var sendMessage: () -> Void = { }
    var pasteImages: ([UIImage]) -> Void = { _ in }
    var updateHeight: () -> Void = { }
    
    var updateActivity: () -> Void = { }
    
    private var updatingInputState = false
    
    private var currentPlaceholder: String?
    
    private var presentationInterfaceState: ChatPresentationInterfaceState?
    
    private var keepSendButtonEnabled = false
    private var extendedSearchLayout = false
    
    private var theme: PresentationTheme?
    private var strings: PresentationStrings?
    
    var inputTextState: ChatTextInputState {
        if let textInputNode = self.textInputNode {
            let text = textInputNode.attributedText?.string ?? ""
            let selectionRange: Range<Int> = textInputNode.selectedRange.location ..< (textInputNode.selectedRange.location + textInputNode.selectedRange.length)
            return ChatTextInputState(inputText: text, selectionRange: selectionRange)
        } else {
            return ChatTextInputState()
        }
    }
    
    override var account: Account? {
        didSet {
            self.micButton.account = self.account
        }
    }
    
    func updateInputTextState(_ state: ChatTextInputState, keepSendButtonEnabled: Bool, extendedSearchLayout: Bool, animated: Bool) {
        if !state.inputText.isEmpty && self.textInputNode == nil {
            self.loadTextInputNode()
        }
        
        if let textInputNode = self.textInputNode {
            self.updatingInputState = true
            var textColor: UIColor = .black
            if let presentationInterfaceState = self.presentationInterfaceState {
                textColor = presentationInterfaceState.theme.chat.inputPanel.inputTextColor
            }
            textInputNode.attributedText = NSAttributedString(string: state.inputText, font: Font.regular(17.0), textColor: textColor)
            textInputNode.selectedRange = NSMakeRange(state.selectionRange.lowerBound, state.selectionRange.count)
            self.updatingInputState = false
            self.keepSendButtonEnabled = keepSendButtonEnabled
            self.extendedSearchLayout = extendedSearchLayout
            self.updateTextNodeText(animated: animated)
        }
    }
    
    func updateKeepSendButtonEnabled(keepSendButtonEnabled: Bool, extendedSearchLayout: Bool, animated: Bool) {
        if keepSendButtonEnabled != self.keepSendButtonEnabled || extendedSearchLayout != self.extendedSearchLayout {
            self.keepSendButtonEnabled = keepSendButtonEnabled
            self.extendedSearchLayout = extendedSearchLayout
            self.updateTextNodeText(animated: animated)
        }
    }
    
    var text: String {
        get {
            return self.textInputNode?.attributedText?.string ?? ""
        } set(value) {
            if let textInputNode = self.textInputNode {
                var textColor: UIColor = .black
                if let presentationInterfaceState = self.presentationInterfaceState {
                    textColor = presentationInterfaceState.theme.chat.inputPanel.inputTextColor
                }
                textInputNode.attributedText = NSAttributedString(string: value, font: Font.regular(17.0), textColor: textColor)
                self.editableTextNodeDidUpdateText(textInputNode)
            }
        }
    }
    
    private let textFieldInsets = UIEdgeInsets(top: 6.0, left: 42.0, bottom: 6.0, right: 42.0)
    private let textInputViewInternalInsets = UIEdgeInsets(top: 1.0, left: 13.0, bottom: 1.0, right: 13.0)
    private let textInputViewRealInsets = UIEdgeInsets(top: 5.5, left: 0.0, bottom: 6.5, right: 0.0)
    private let accessoryButtonSpacing: CGFloat = 0.0
    private let accessoryButtonInset: CGFloat = 4.0 + UIScreenPixel
    
    init(theme: PresentationTheme, presentController: @escaping (ViewController) -> Void) {
        self.textInputContainer = ASDisplayNode()
        self.textInputContainer.clipsToBounds = true
        self.textInputContainer.backgroundColor = theme.chat.inputPanel.inputBackgroundColor
        
        self.textInputBackgroundView = UIImageView()
        self.textPlaceholderNode = TextNode()
        self.textPlaceholderNode.isLayerBacked = true
        self.attachmentButton = HighlightableButton()
        self.searchLayoutClearButton = HighlightableButton()
        self.searchLayoutProgressView = UIImageView(image: searchLayoutProgressImage)
        self.searchLayoutProgressView.isHidden = true
        self.micButton = ChatTextInputMediaRecordingButton(theme: theme, presentController: presentController)
        self.sendButton = HighlightableButton()
        
        super.init()
        
        self.attachmentButton.addTarget(self, action: #selector(self.attachmentButtonPressed), for: .touchUpInside)
        self.view.addSubview(self.attachmentButton)
        
        self.micButton.beginRecording = { [weak self] in
            if let strongSelf = self, let presentationInterfaceState = strongSelf.presentationInterfaceState, let interfaceInteraction = strongSelf.interfaceInteraction {
                let isVideo: Bool
                switch presentationInterfaceState.interfaceState.mediaRecordingMode {
                    case .audio:
                        isVideo = false
                    case .video:
                        isVideo = true
                }
                interfaceInteraction.beginMediaRecording(isVideo)
            }
        }
        self.micButton.endRecording = { [weak self] sendMedia in
            if let strongSelf = self, let interfaceState = strongSelf.presentationInterfaceState, let interfaceInteraction = strongSelf.interfaceInteraction, let _ = interfaceState.inputTextPanelState.mediaRecordingState {
                if sendMedia {
                    interfaceInteraction.finishMediaRecording(.send)
                } else {
                    interfaceInteraction.finishMediaRecording(.dismiss)
                }
            }
        }
        self.micButton.offsetRecordingControls = { [weak self] in
            if let strongSelf = self, let presentationInterfaceState = strongSelf.presentationInterfaceState {
                if let (width, leftInset, rightInset, maxHeight) = strongSelf.validLayout {
                    let _ = strongSelf.updateLayout(width: width, leftInset: leftInset, rightInset: rightInset, maxHeight: maxHeight, transition: .immediate, interfaceState: presentationInterfaceState)
                }
            }
        }
        self.micButton.stopRecording = { [weak self] in
            if let strongSelf = self, let interfaceInteraction = strongSelf.interfaceInteraction {
                interfaceInteraction.stopMediaRecording()
            }
        }
        self.micButton.updateLocked = { [weak self] _ in
            if let strongSelf = self, let interfaceInteraction = strongSelf.interfaceInteraction {
                interfaceInteraction.lockMediaRecording()
            }
        }
        self.micButton.switchMode = { [weak self] in
            if let strongSelf = self, let interfaceInteraction = strongSelf.interfaceInteraction {
                interfaceInteraction.switchMediaRecordingMode()
            }
        }
        self.view.addSubview(self.micButton)
        
        self.sendButton.addTarget(self, action: #selector(self.sendButtonPressed), for: .touchUpInside)
        self.sendButton.alpha = 0.0
        self.view.addSubview(self.sendButton)
        
        self.searchLayoutClearButton.addTarget(self, action: #selector(self.searchLayoutClearButtonPressed), for: .touchUpInside)
        self.searchLayoutClearButton.alpha = 0.0
        
        self.searchLayoutClearButton.addSubview(self.searchLayoutProgressView)
        
        self.addSubnode(self.textInputContainer)
        self.view.addSubview(self.textInputBackgroundView)
        
        self.addSubnode(self.textPlaceholderNode)
        
        self.view.addSubview(self.searchLayoutClearButton)
        
        self.textInputBackgroundView.clipsToBounds = true
        let recognizer = TouchDownGestureRecognizer(target: self, action: #selector(self.textInputBackgroundViewTap(_:)))
        recognizer.touchDown = { [weak self] in
            if let strongSelf = self {
                strongSelf.ensureFocused()
            }
        }
        self.textInputBackgroundView.addGestureRecognizer(recognizer)
        self.textInputBackgroundView.isUserInteractionEnabled = true
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func loadTextInputNode() {
        let textInputNode = ASEditableTextNode()
        var textColor: UIColor = .black
        var tintColor: UIColor = .blue
        var baseFontSize: CGFloat = 17.0
        var keyboardAppearance: UIKeyboardAppearance = UIKeyboardAppearance.default
        if let presentationInterfaceState = self.presentationInterfaceState {
            textColor = presentationInterfaceState.theme.chat.inputPanel.inputTextColor
            tintColor = presentationInterfaceState.theme.list.itemAccentColor
            //baseFontSize = presentationInterfaceState.fontSize.baseDisplaySize
            switch presentationInterfaceState.theme.chat.inputPanel.keyboardColor {
                case .light:
                    keyboardAppearance = .default
                case .dark:
                    keyboardAppearance = .dark
            }
        }
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 1.0
        paragraphStyle.lineHeightMultiple = 1.0
        paragraphStyle.paragraphSpacing = 1.0
        paragraphStyle.maximumLineHeight = 20.0
        paragraphStyle.minimumLineHeight = 20.0
        
        textInputNode.typingAttributes = [NSAttributedStringKey.font.rawValue: Font.regular(max(17.0, baseFontSize)), NSAttributedStringKey.foregroundColor.rawValue: textColor, NSAttributedStringKey.paragraphStyle.rawValue: paragraphStyle]
        textInputNode.clipsToBounds = false
        textInputNode.textView.clipsToBounds = false
        textInputNode.delegate = self
        textInputNode.hitTestSlop = UIEdgeInsets(top: -5.0, left: -5.0, bottom: -5.0, right: -5.0)
        textInputNode.keyboardAppearance = keyboardAppearance
        textInputNode.textContainerInset = UIEdgeInsets(top: self.textInputViewRealInsets.top, left: 0.0, bottom: self.textInputViewRealInsets.bottom, right: 0.0)
        textInputNode.tintColor = tintColor
        textInputNode.textView.scrollIndicatorInsets = UIEdgeInsets(top: 9.0, left: 0.0, bottom: 9.0, right: -13.0)
        self.textInputContainer.addSubnode(textInputNode)
        self.textInputNode = textInputNode
        
        if !self.textInputContainer.bounds.size.width.isZero {
            let textInputFrame = self.textInputContainer.frame
            
            var accessoryButtonsWidth: CGFloat = 0.0
            var firstButton = true
            for (_, button) in self.accessoryItemButtons {
                if firstButton {
                    firstButton = false
                    accessoryButtonsWidth += accessoryButtonInset
                } else {
                    accessoryButtonsWidth += accessoryButtonSpacing
                }
                accessoryButtonsWidth += button.buttonWidth
            }
            
            textInputNode.frame = CGRect(origin: CGPoint(x: self.textInputViewInternalInsets.left, y: self.textInputViewInternalInsets.top), size: CGSize(width: textInputFrame.size.width - (self.textInputViewInternalInsets.left + self.textInputViewInternalInsets.right + accessoryButtonsWidth), height: textInputFrame.size.height - self.textInputViewInternalInsets.top - self.textInputViewInternalInsets.bottom))
        }
        
        self.textInputBackgroundView.isUserInteractionEnabled = false
        self.textInputBackgroundView.removeGestureRecognizer(self.textInputBackgroundView.gestureRecognizers![0])
        
        let recognizer = TouchDownGestureRecognizer(target: self, action: #selector(self.textInputBackgroundViewTap(_:)))
        recognizer.touchDown = { [weak self] in
            if let strongSelf = self {
                strongSelf.ensureFocused()
            }
        }
        textInputNode.view.addGestureRecognizer(recognizer)
    }
    
    private func textFieldMaxHeight(_ maxHeight: CGFloat) -> CGFloat {
        return max(33.0, maxHeight - (self.textFieldInsets.top + self.textFieldInsets.bottom + self.textInputViewInternalInsets.top + self.textInputViewInternalInsets.bottom))
    }
    
    private func calculateTextFieldMetrics(width: CGFloat, maxHeight: CGFloat) -> (accessoryButtonsWidth: CGFloat, textFieldHeight: CGFloat) {
        let accessoryButtonInset = self.accessoryButtonInset
        let accessoryButtonSpacing = self.accessoryButtonSpacing
        
        let fieldMaxHeight = textFieldMaxHeight(maxHeight)
        
        var accessoryButtonsWidth: CGFloat = 0.0
        var firstButton = true
        for (_, button) in self.accessoryItemButtons {
            if firstButton {
                firstButton = false
                accessoryButtonsWidth += accessoryButtonInset
            } else {
                accessoryButtonsWidth += accessoryButtonSpacing
            }
            accessoryButtonsWidth += button.buttonWidth
        }
        
        let textFieldHeight: CGFloat
        if let textInputNode = self.textInputNode {
            let unboundTextFieldHeight = max(33.0, ceil(textInputNode.measure(CGSize(width: width - self.textFieldInsets.left - self.textFieldInsets.right - self.textInputViewInternalInsets.left - self.textInputViewInternalInsets.right - accessoryButtonsWidth, height: CGFloat.greatestFiniteMagnitude)).height))
            
            let maxNumberOfLines = min(12, (Int(fieldMaxHeight - 11.0) - 33) / 22)
            
            let updatedMaxHeight = (CGFloat(maxNumberOfLines) * 22.0 + 10.0)
            
            textFieldHeight = min(updatedMaxHeight, unboundTextFieldHeight)
        } else {
            textFieldHeight = 33.0
        }
        
        return (accessoryButtonsWidth, textFieldHeight)
    }
    
    private func panelHeight(textFieldHeight: CGFloat) -> CGFloat {
        return textFieldHeight + self.textFieldInsets.top + self.textFieldInsets.bottom + self.textInputViewInternalInsets.top + self.textInputViewInternalInsets.bottom
    }
    
    override func updateLayout(width: CGFloat, leftInset: CGFloat, rightInset: CGFloat, maxHeight: CGFloat, transition: ContainedViewLayoutTransition, interfaceState: ChatPresentationInterfaceState) -> CGFloat {
        self.validLayout = (width, leftInset, rightInset, maxHeight)
        let baseWidth = width - leftInset - rightInset
        if self.presentationInterfaceState != interfaceState {
            let previousState = self.presentationInterfaceState
            self.presentationInterfaceState = interfaceState
            
            var updateSendButtonIcon = false
            if (previousState?.interfaceState.editMessage != nil) != (interfaceState.interfaceState.editMessage != nil) {
                updateSendButtonIcon = true
            }
            if self.theme !== interfaceState.theme {
                updateSendButtonIcon = true
                
                if self.theme == nil || !self.theme!.chat.inputPanel.inputTextColor.isEqual(interfaceState.theme.chat.inputPanel.inputTextColor) {
                    let textColor = interfaceState.theme.chat.inputPanel.inputTextColor
                    
                    if let textInputNode = self.textInputNode {
                        if let text = textInputNode.attributedText?.string {
                            let range = textInputNode.selectedRange
                            textInputNode.attributedText = NSAttributedString(string: text, font: Font.regular(17.0), textColor: textColor)
                            textInputNode.selectedRange = range
                        }
                        textInputNode.typingAttributes = [NSAttributedStringKey.font.rawValue: Font.regular(17.0), NSAttributedStringKey.foregroundColor.rawValue: textColor]
                    }
                }
                
                let keyboardAppearance: UIKeyboardAppearance
                switch interfaceState.theme.chat.inputPanel.keyboardColor {
                    case .light:
                        keyboardAppearance = .default
                    case .dark:
                        keyboardAppearance = .dark
                }
                self.textInputNode?.keyboardAppearance = keyboardAppearance
                
                self.textInputContainer.backgroundColor = interfaceState.theme.chat.inputPanel.inputBackgroundColor
                
                self.theme = interfaceState.theme
                
                
                self.attachmentButton.setImage(PresentationResourcesChat.chatInputPanelAttachmentButtonImage(interfaceState.theme), for: [])
               
                self.micButton.updateTheme(theme: interfaceState.theme)
                
                self.textInputBackgroundView.image = PresentationResourcesChat.chatInputTextFieldBackgroundImage(interfaceState.theme)
                
                self.searchLayoutClearButton.setImage(PresentationResourcesChat.chatInputTextFieldClearImage(interfaceState.theme), for: [])
                
                if let audioRecordingDotNode = self.audioRecordingDotNode {
                    audioRecordingDotNode.image = PresentationResourcesChat.chatInputPanelMediaRecordingDotImage(interfaceState.theme)
                }
                
                self.audioRecordingTimeNode?.updateTheme(theme: interfaceState.theme)
                self.audioRecordingCancelIndicator?.updateTheme(theme: interfaceState.theme)
                
                for (_, button) in self.accessoryItemButtons {
                    button.updateThemeAndStrings(theme: interfaceState.theme, strings: interfaceState.strings)
                }
            } else if self.strings !== interfaceState.strings {
                self.strings = interfaceState.strings
                
                for (_, button) in self.accessoryItemButtons {
                    button.updateThemeAndStrings(theme: interfaceState.theme, strings: interfaceState.strings)
                }
            }
            
            if let peer = interfaceState.peer, previousState?.peer == nil || !peer.isEqual(previousState!.peer!) {
                let placeholder: String
                if let channel = peer as? TelegramChannel, case .broadcast = channel.info {
                    placeholder = interfaceState.strings.Conversation_InputTextBroadcastPlaceholder
                } else {
                    placeholder = interfaceState.strings.Conversation_InputTextPlaceholder
                }
                if self.currentPlaceholder != placeholder {
                    self.currentPlaceholder = placeholder
                    let placeholderLayout = TextNode.asyncLayout(self.textPlaceholderNode)
                    let (placeholderSize, placeholderApply) = placeholderLayout(TextNodeLayoutArguments(attributedString: NSAttributedString(string: placeholder, font: Font.regular(17.0), textColor: interfaceState.theme.chat.inputPanel.inputPlaceholderColor), backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: 320.0, height: CGFloat.greatestFiniteMagnitude), alignment: .natural, cutout: nil, insets: UIEdgeInsets()))
                    self.textPlaceholderNode.frame = CGRect(origin: self.textPlaceholderNode.frame.origin, size: placeholderSize.size)
                    let _ = placeholderApply()
                }
            }
            
            let sendButtonHasApplyIcon = interfaceState.interfaceState.editMessage != nil
            
            if updateSendButtonIcon {
                if !self.animatingSendButton {
                    if transition.isAnimated && !self.sendButton.alpha.isZero && self.sendButton.layer.animation(forKey: "opacity") == nil, let imageView = self.sendButton.imageView, let previousImage = imageView.image {
                        let tempView = UIImageView(image: previousImage)
                        self.sendButton.addSubview(tempView)
                        tempView.frame = imageView.frame
                        tempView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { [weak tempView] _ in
                            tempView?.removeFromSuperview()
                        })
                        tempView.layer.animateScale(from: 1.0, to: 0.2, duration: 0.2, removeOnCompletion: false)
                        
                        imageView.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                        imageView.layer.animateScale(from: 0.2, to: 1.0, duration: 0.2)
                    }
                    self.sendButtonHasApplyIcon = sendButtonHasApplyIcon
                    if self.sendButtonHasApplyIcon {
                        self.sendButton.setImage(PresentationResourcesChat.chatInputPanelApplyButtonImage(interfaceState.theme), for: [])
                    } else {
                        self.sendButton.setImage(PresentationResourcesChat.chatInputPanelSendButtonImage(interfaceState.theme), for: [])
                    }
                }
            }
        }
        
        let minimalHeight: CGFloat = 47.0
        let minimalInputHeight: CGFloat = 35.0
        
        var animatedTransition = true
        if case .immediate = transition {
            animatedTransition = false
        }
        
        var updateAccessoryButtons = false
        if self.presentationInterfaceState?.inputTextPanelState.accessoryItems.count == self.accessoryItemButtons.count {
            for i in 0 ..< interfaceState.inputTextPanelState.accessoryItems.count {
                if interfaceState.inputTextPanelState.accessoryItems[i] != self.accessoryItemButtons[i].0 {
                    updateAccessoryButtons = true
                    break
                }
            }
        } else {
            updateAccessoryButtons = true
        }
        
        var removeAccessoryButtons: [AccessoryItemIconButton]?
        if updateAccessoryButtons {
            var updatedButtons: [(ChatTextInputAccessoryItem, AccessoryItemIconButton)] = []
            for item in interfaceState.inputTextPanelState.accessoryItems {
                var itemAndButton: (ChatTextInputAccessoryItem, AccessoryItemIconButton)?
                for i in 0 ..< self.accessoryItemButtons.count {
                    if self.accessoryItemButtons[i].0 == item {
                        itemAndButton = self.accessoryItemButtons[i]
                        self.accessoryItemButtons.remove(at: i)
                        break
                    }
                }
                if itemAndButton == nil {
                    let button = AccessoryItemIconButton(item: item, theme: interfaceState.theme, strings: interfaceState.strings)
                    button.addTarget(self, action: #selector(self.accessoryItemButtonPressed(_:)), for: [.touchUpInside])
                    itemAndButton = (item, button)
                }
                updatedButtons.append(itemAndButton!)
            }
            for (_, button) in self.accessoryItemButtons {
                if animatedTransition {
                    if removeAccessoryButtons == nil {
                        removeAccessoryButtons = []
                    }
                    removeAccessoryButtons!.append(button)
                } else {
                    button.removeFromSuperview()
                }
            }
            self.accessoryItemButtons = updatedButtons
        }
        
        let (accessoryButtonsWidth, textFieldHeight) = self.calculateTextFieldMetrics(width: baseWidth, maxHeight: maxHeight)
        let panelHeight = self.panelHeight(textFieldHeight: textFieldHeight)
        
        self.micButton.updateMode(mode: interfaceState.interfaceState.mediaRecordingMode, animated: transition.isAnimated)
        
        var hideMicButton = false
        var audioRecordingItemsVerticalOffset: CGFloat = 0.0
        if let mediaRecordingState = interfaceState.inputTextPanelState.mediaRecordingState {
            audioRecordingItemsVerticalOffset = panelHeight * 2.0
            transition.updateAlpha(layer: self.textInputBackgroundView.layer, alpha: 0.0)
            if let textInputNode = self.textInputNode {
                transition.updateAlpha(node: textInputNode, alpha: 0.0)
            }
            for (_, button) in self.accessoryItemButtons {
                transition.updateAlpha(layer: button.layer, alpha: 0.0)
            }
            
            switch mediaRecordingState {
                case let .audio(recorder, isLocked):
                    self.micButton.audioRecorder = recorder
                    let audioRecordingInfoContainerNode: ASDisplayNode
                    if let currentAudioRecordingInfoContainerNode = self.audioRecordingInfoContainerNode {
                        audioRecordingInfoContainerNode = currentAudioRecordingInfoContainerNode
                    } else {
                        audioRecordingInfoContainerNode = ASDisplayNode()
                        self.audioRecordingInfoContainerNode = audioRecordingInfoContainerNode
                        self.insertSubnode(audioRecordingInfoContainerNode, at: 0)
                    }
                    
                    var animateCancelSlideIn = false
                    let audioRecordingCancelIndicator: ChatTextInputAudioRecordingCancelIndicator
                    if let currentAudioRecordingCancelIndicator = self.audioRecordingCancelIndicator {
                        audioRecordingCancelIndicator = currentAudioRecordingCancelIndicator
                    } else {
                        animateCancelSlideIn = transition.isAnimated
                        
                        audioRecordingCancelIndicator = ChatTextInputAudioRecordingCancelIndicator(theme: interfaceState.theme, strings: interfaceState.strings, cancel: { [weak self] in
                            self?.interfaceInteraction?.finishMediaRecording(.dismiss)
                        })
                        self.audioRecordingCancelIndicator = audioRecordingCancelIndicator
                        self.insertSubnode(audioRecordingCancelIndicator, at: 0)
                    }
                    
                    audioRecordingCancelIndicator.frame = CGRect(origin: CGPoint(x: leftInset + floor((baseWidth - audioRecordingCancelIndicator.bounds.size.width) / 2.0) - self.micButton.controlsOffset, y: panelHeight - minimalHeight + floor((minimalHeight - audioRecordingCancelIndicator.bounds.size.height) / 2.0)), size: audioRecordingCancelIndicator.bounds.size)
                    
                    if animateCancelSlideIn {
                        let position = audioRecordingCancelIndicator.layer.position
                        audioRecordingCancelIndicator.layer.animatePosition(from: CGPoint(x: width + audioRecordingCancelIndicator.bounds.size.width, y: position.y), to: position, duration: 0.4, timingFunction: kCAMediaTimingFunctionSpring)
                    }
                    
                    audioRecordingCancelIndicator.updateIsDisplayingCancel(isLocked, animated: !animateCancelSlideIn)
                    
                    var animateTimeSlideIn = false
                    let audioRecordingTimeNode: ChatTextInputAudioRecordingTimeNode
                    if let currentAudioRecordingTimeNode = self.audioRecordingTimeNode {
                        audioRecordingTimeNode = currentAudioRecordingTimeNode
                    } else {
                        audioRecordingTimeNode = ChatTextInputAudioRecordingTimeNode(theme: interfaceState.theme)
                        self.audioRecordingTimeNode = audioRecordingTimeNode
                        audioRecordingInfoContainerNode.addSubnode(audioRecordingTimeNode)
                        
                        if transition.isAnimated {
                            animateTimeSlideIn = true
                        }
                    }
                    
                    let audioRecordingTimeSize = audioRecordingTimeNode.measure(CGSize(width: 200.0, height: 100.0))
                    
                    audioRecordingInfoContainerNode.frame = CGRect(origin: CGPoint(x: min(leftInset, audioRecordingCancelIndicator.frame.minX - audioRecordingTimeSize.width - 8.0 - 28.0), y: 0.0), size: CGSize(width: baseWidth, height: panelHeight))
                    
                    audioRecordingTimeNode.frame = CGRect(origin: CGPoint(x: 28.0, y: panelHeight - minimalHeight + floor((minimalHeight - audioRecordingTimeSize.height) / 2.0)), size: audioRecordingTimeSize)
                    if animateTimeSlideIn {
                        let position = audioRecordingTimeNode.layer.position
                        audioRecordingTimeNode.layer.animatePosition(from: CGPoint(x: position.x - 28.0 - audioRecordingTimeSize.width, y: position.y), to: position, duration: 0.5, timingFunction: kCAMediaTimingFunctionSpring)
                    }
                    
                    audioRecordingTimeNode.audioRecorder = recorder
                    
                    var animateDotSlideIn = false
                    let audioRecordingDotNode: ASImageNode
                    if let currentAudioRecordingDotNode = self.audioRecordingDotNode {
                        audioRecordingDotNode = currentAudioRecordingDotNode
                    } else {
                        animateDotSlideIn = transition.isAnimated
                        
                        audioRecordingDotNode = ASImageNode()
                        audioRecordingDotNode.image = PresentationResourcesChat.chatInputPanelMediaRecordingDotImage(interfaceState.theme)
                        self.audioRecordingDotNode = audioRecordingDotNode
                        audioRecordingInfoContainerNode.addSubnode(audioRecordingDotNode)
                    }
                    audioRecordingDotNode.frame = CGRect(origin: CGPoint(x: audioRecordingTimeNode.frame.minX - 17.0, y: panelHeight - minimalHeight + floor((minimalHeight - 9.0) / 2.0)), size: CGSize(width: 9.0, height: 9.0))
                    if animateDotSlideIn {
                        let position = audioRecordingDotNode.layer.position
                        audioRecordingDotNode.layer.animatePosition(from: CGPoint(x: position.x - 9.0 - 51.0, y: position.y), to: position, duration: 0.7, timingFunction: kCAMediaTimingFunctionSpring, completion: { [weak audioRecordingDotNode] finished in
                            if finished {
                                let animation = CAKeyframeAnimation(keyPath: "opacity")
                                animation.values = [1.0 as NSNumber, 1.0 as NSNumber, 0.0 as NSNumber]
                                animation.keyTimes = [0.0 as NSNumber, 0.4546 as NSNumber, 0.9091 as NSNumber, 1 as NSNumber]
                                animation.duration = 0.5
                                animation.autoreverses = true
                                animation.repeatCount = Float.infinity
                                
                                audioRecordingDotNode?.layer.add(animation, forKey: "recording")
                            }
                        })
                    }
                case let .video(status, _):
                    switch status {
                        case let .recording(recordingStatus):
                            self.micButton.videoRecordingStatus = recordingStatus
                        case .editing:
                            self.micButton.videoRecordingStatus = nil
                            hideMicButton = true
                    }
            }
        } else {
            self.micButton.audioRecorder = nil
            self.micButton.videoRecordingStatus = nil
            transition.updateAlpha(layer: self.textInputBackgroundView.layer, alpha: 1.0)
            if let textInputNode = self.textInputNode {
                transition.updateAlpha(node: textInputNode, alpha: 1.0)
            }
            for (_, button) in self.accessoryItemButtons {
                transition.updateAlpha(layer: button.layer, alpha: 1.0)
            }
            
            if let audioRecordingInfoContainerNode = self.audioRecordingInfoContainerNode {
                self.audioRecordingInfoContainerNode = nil
                transition.updateFrame(node: audioRecordingInfoContainerNode, frame: CGRect(origin: CGPoint(x: -width, y: 0.0), size: audioRecordingInfoContainerNode.bounds.size), completion: { [weak audioRecordingInfoContainerNode] _ in
                    audioRecordingInfoContainerNode?.removeFromSupernode()
                })
            }
            
            if let _ = self.audioRecordingDotNode {
                self.audioRecordingDotNode = nil
            }
            
            if let _ = self.audioRecordingTimeNode {
                self.audioRecordingTimeNode = nil
            }
            
            if let audioRecordingCancelIndicator = self.audioRecordingCancelIndicator {
                self.audioRecordingCancelIndicator = nil
                if transition.isAnimated {
                    if audioRecordingCancelIndicator.isDisplayingCancel {
                        audioRecordingCancelIndicator.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.25, removeOnCompletion: false)
                        audioRecordingCancelIndicator.layer.animatePosition(from: CGPoint(), to: CGPoint(x: 0.0, y: -22.0), duration: 0.25, removeOnCompletion: false, additive: true, completion: { [weak audioRecordingCancelIndicator] _ in
                            audioRecordingCancelIndicator?.removeFromSupernode()
                        })
                    } else {
                        let position = audioRecordingCancelIndicator.layer.position
                        audioRecordingCancelIndicator.layer.animatePosition(from: position, to: CGPoint(x: 0.0 - audioRecordingCancelIndicator.bounds.size.width, y: position.y), duration: 0.3, removeOnCompletion: false, completion: { [weak audioRecordingCancelIndicator] _ in
                            audioRecordingCancelIndicator?.removeFromSupernode()
                        })
                    }
                } else {
                    audioRecordingCancelIndicator.removeFromSupernode()
                }
            }
        }
        
        transition.updateFrame(layer: self.attachmentButton.layer, frame: CGRect(origin: CGPoint(x: leftInset + 2.0 - UIScreenPixel, y: panelHeight - minimalHeight + audioRecordingItemsVerticalOffset), size: CGSize(width: 40.0, height: minimalHeight)))
        
        var composeButtonsOffset: CGFloat = 0.0
        var textInputBackgroundWidthOffset: CGFloat = 0.0
        if self.extendedSearchLayout {
            composeButtonsOffset = 44.0
            textInputBackgroundWidthOffset = 36.0
        }
        
        transition.updateFrame(layer: self.micButton.layer, frame: CGRect(origin: CGPoint(x: width - rightInset - 43.0 - UIScreenPixel + composeButtonsOffset, y: panelHeight - minimalHeight - UIScreenPixel), size: CGSize(width: 44.0, height: minimalHeight)))
        self.micButton.layoutItems()
        transition.updateFrame(layer: self.sendButton.layer, frame: CGRect(origin: CGPoint(x: width - rightInset - 43.0 - UIScreenPixel + composeButtonsOffset, y: panelHeight - minimalHeight - UIScreenPixel), size: CGSize(width: 44.0, height: minimalHeight)))
        
        let searchLayoutClearButtonSize = CGSize(width: 44.0, height: minimalHeight)
        transition.updateFrame(layer: self.searchLayoutClearButton.layer, frame: CGRect(origin: CGPoint(x: width - rightInset - self.textFieldInsets.left - self.textFieldInsets.right + textInputBackgroundWidthOffset + 3.0, y: panelHeight - minimalHeight), size: searchLayoutClearButtonSize))

        let searchProgressSize = self.searchLayoutProgressView.bounds.size
        transition.updateFrame(layer: self.searchLayoutProgressView.layer, frame: CGRect(origin: CGPoint(x: floor((searchLayoutClearButtonSize.width - searchProgressSize.width) / 2.0), y: floor((searchLayoutClearButtonSize.height - searchProgressSize.height) / 2.0)), size: searchProgressSize))
        
        let textInputFrame = CGRect(x: leftInset + self.textFieldInsets.left, y: self.textFieldInsets.top + audioRecordingItemsVerticalOffset, width: baseWidth - self.textFieldInsets.left - self.textFieldInsets.right, height: panelHeight - self.textFieldInsets.top - self.textFieldInsets.bottom)
        transition.updateFrame(node: self.textInputContainer, frame: textInputFrame)
        
        if let textInputNode = self.textInputNode {
            let textFieldFrame = CGRect(origin: CGPoint(x: self.textInputViewInternalInsets.left, y: self.textInputViewInternalInsets.top), size: CGSize(width: textInputFrame.size.width - (self.textInputViewInternalInsets.left + self.textInputViewInternalInsets.right + accessoryButtonsWidth), height: textInputFrame.size.height - self.textInputViewInternalInsets.top - textInputViewInternalInsets.bottom))
            let shouldUpdateLayout = textFieldFrame.size != textInputNode.frame.size
            transition.updateFrame(node: textInputNode, frame: textFieldFrame)
            if shouldUpdateLayout {
                textInputNode.layout()
            }
        }
        
        if let contextPlaceholder = interfaceState.inputTextPanelState.contextPlaceholder {
            let placeholderLayout = TextNode.asyncLayout(self.contextPlaceholderNode)
            let (placeholderSize, placeholderApply) = placeholderLayout(TextNodeLayoutArguments(attributedString: contextPlaceholder, backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: width - leftInset - rightInset - self.textFieldInsets.left - self.textFieldInsets.right - self.textInputViewInternalInsets.left - self.textInputViewInternalInsets.right - accessoryButtonsWidth, height: CGFloat.greatestFiniteMagnitude), alignment: .natural, cutout: nil, insets: UIEdgeInsets()))
            let contextPlaceholderNode = placeholderApply()
            if let currentContextPlaceholderNode = self.contextPlaceholderNode, currentContextPlaceholderNode !== contextPlaceholderNode {
                self.contextPlaceholderNode = nil
                currentContextPlaceholderNode.removeFromSupernode()
            }
            
            if self.contextPlaceholderNode !== contextPlaceholderNode {
                contextPlaceholderNode.displaysAsynchronously = false
                self.contextPlaceholderNode = contextPlaceholderNode
                self.insertSubnode(contextPlaceholderNode, aboveSubnode: self.textPlaceholderNode)
            }
            
            let _ = placeholderApply()
            
            contextPlaceholderNode.frame = CGRect(origin: CGPoint(x: leftInset + self.textFieldInsets.left + self.textInputViewInternalInsets.left, y: self.textFieldInsets.top + self.textInputViewInternalInsets.top + self.textInputViewRealInsets.top + audioRecordingItemsVerticalOffset + UIScreenPixel), size: placeholderSize.size)
            
            self.textPlaceholderNode.isHidden = true
        } else if let contextPlaceholderNode = self.contextPlaceholderNode {
            self.contextPlaceholderNode = nil
            contextPlaceholderNode.removeFromSupernode()
            self.textPlaceholderNode.alpha = 1.0
            
            var hasText = false
            if let textInputNode = self.textInputNode, let attributedText = textInputNode.attributedText, attributedText.length != 0 {
                hasText = true
            }
            self.textPlaceholderNode.isHidden = hasText
        }
        
        transition.updateFrame(node: self.textPlaceholderNode, frame: CGRect(origin: CGPoint(x: leftInset + self.textFieldInsets.left + self.textInputViewInternalInsets.left, y: self.textFieldInsets.top + self.textInputViewInternalInsets.top + self.textInputViewRealInsets.top + audioRecordingItemsVerticalOffset + UIScreenPixel), size: self.textPlaceholderNode.frame.size))
        
        transition.updateFrame(layer: self.textInputBackgroundView.layer, frame: CGRect(x: leftInset + self.textFieldInsets.left, y: self.textFieldInsets.top + audioRecordingItemsVerticalOffset, width: baseWidth - self.textFieldInsets.left - self.textFieldInsets.right + textInputBackgroundWidthOffset, height: panelHeight - self.textFieldInsets.top - self.textFieldInsets.bottom))
        
        var nextButtonTopRight = CGPoint(x: width - rightInset - self.textFieldInsets.right - accessoryButtonInset, y: panelHeight - self.textFieldInsets.bottom - minimalInputHeight + audioRecordingItemsVerticalOffset)
        for (_, button) in self.accessoryItemButtons.reversed() {
            let buttonSize = CGSize(width: button.buttonWidth, height: minimalInputHeight)
            let buttonFrame = CGRect(origin: CGPoint(x: nextButtonTopRight.x - buttonSize.width, y: nextButtonTopRight.y + floor((minimalInputHeight - buttonSize.height) / 2.0)), size: buttonSize)
            if button.superview == nil {
                self.view.addSubview(button)
                button.frame = buttonFrame
                transition.updateFrame(layer: button.layer, frame: buttonFrame)
                if animatedTransition {
                    button.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
                    button.layer.animateScale(from: 0.2, to: 1.0, duration: 0.25)
                }
            } else {
                transition.updateFrame(layer: button.layer, frame: buttonFrame)
            }
            nextButtonTopRight.x -= buttonSize.width
            nextButtonTopRight.x -= accessoryButtonSpacing
        }
        
        if let removeAccessoryButtons = removeAccessoryButtons {
            for button in removeAccessoryButtons {
                let buttonFrame = CGRect(origin: CGPoint(x: button.frame.origin.x, y: panelHeight - self.textFieldInsets.bottom - minimalInputHeight), size: button.frame.size)
                transition.updateFrame(layer: button.layer, frame: buttonFrame)
                button.layer.animateScale(from: 1.0, to: 0.2, duration: 0.25, removeOnCompletion: false)
                button.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.25, removeOnCompletion: false, completion: { [weak button] _ in
                    button?.removeFromSuperview()
                })
            }
        }
        
        if let textInputNode = self.textInputNode, let attributedText = textInputNode.attributedText, attributedText.length != 0 {
            hideMicButton = true
        }
        
        if self.extendedSearchLayout {
            hideMicButton = true
        }
        
        if hideMicButton {
            if !self.micButton.alpha.isZero {
                transition.updateAlpha(layer: self.micButton.layer, alpha: 0.0)
            }
        } else {
            if self.micButton.alpha.isZero {
                transition.updateAlpha(layer: self.micButton.layer, alpha: 1.0)
            }
        }
        
        return panelHeight
    }
    
    @objc func editableTextNodeDidUpdateText(_ editableTextNode: ASEditableTextNode) {
        if let _ = self.textInputNode {
            let inputTextState = self.inputTextState
            self.interfaceInteraction?.updateTextInputState({ _ in return inputTextState })
            self.updateTextNodeText(animated: true)
        }
    }
    
    private func updateTextNodeText(animated: Bool) {
        var hasText = false
        var hideMicButton = false
        if let textInputNode = self.textInputNode, let attributedText = textInputNode.attributedText, attributedText.length != 0 {
            hasText = true
            hideMicButton = true
        }
        self.textPlaceholderNode.isHidden = hasText
        
        if let presentationInterfaceState = self.presentationInterfaceState {
            if let mediaRecordingState = presentationInterfaceState.inputTextPanelState.mediaRecordingState {
                if case .video(.editing, false) = mediaRecordingState {
                    hideMicButton = true
                }
            }
        }
        
        var animateWithBounce = false
        if self.extendedSearchLayout {
            hideMicButton = true
            
            if !self.sendButton.alpha.isZero {
                self.sendButton.alpha = 0.0
                if animated {
                    self.animatingSendButton = true
                    self.sendButton.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, completion: { [weak self] _ in
                        if let strongSelf = self {
                            strongSelf.animatingSendButton = false
                            strongSelf.applyUpdateSendButtonIcon()
                        }
                    })
                    self.sendButton.layer.animateScale(from: 1.0, to: 0.2, duration: 0.2)
                }
            }
            if self.searchLayoutClearButton.alpha.isZero {
                self.searchLayoutClearButton.alpha = 1.0
                if animated {
                    self.searchLayoutClearButton.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.1)
                    self.searchLayoutClearButton.layer.animateScale(from: 0.8, to: 1.0, duration: 0.2)
                }
            }
        } else {
            animateWithBounce = true
            if !self.searchLayoutClearButton.alpha.isZero {
                animateWithBounce = false
                self.searchLayoutClearButton.alpha = 0.0
                if animated {
                    self.searchLayoutClearButton.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2)
                    self.searchLayoutClearButton.layer.animateScale(from: 1.0, to: 0.8, duration: 0.2)
                }
            }
            
            if hasText || self.keepSendButtonEnabled {
                hideMicButton = true
                if self.sendButton.alpha.isZero {
                    self.sendButton.alpha = 1.0
                    if animated {
                        self.sendButton.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.1)
                        if animateWithBounce {
                            self.sendButton.layer.animateSpring(from: NSNumber(value: Float(0.1)), to: NSNumber(value: Float(1.0)), keyPath: "transform.scale", duration: 0.6)
                        } else {
                            self.sendButton.layer.animateScale(from: 0.2, to: 1.0, duration: 0.25)
                        }
                    }
                }
            } else {
                if !self.sendButton.alpha.isZero {
                    self.sendButton.alpha = 0.0
                    if animated {
                        self.animatingSendButton = true
                        self.sendButton.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, completion: { [weak self] _ in
                            if let strongSelf = self {
                                strongSelf.animatingSendButton = false
                                strongSelf.applyUpdateSendButtonIcon()
                            }
                        })
                    }
                }
            }
        }
        
        if hideMicButton {
            if !self.micButton.alpha.isZero {
                self.micButton.alpha = 0.0
                if animated {
                    self.micButton.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2)
                }
            }
        } else {
            if self.micButton.alpha.isZero {
                self.micButton.alpha = 1.0
                if animated {
                    self.micButton.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.1)
                    if animateWithBounce {
                        self.micButton.layer.animateSpring(from: NSNumber(value: Float(0.1)), to: NSNumber(value: Float(1.0)), keyPath: "transform.scale", duration: 0.6)
                    } else {
                        self.micButton.layer.animateScale(from: 0.2, to: 1.0, duration: 0.25)
                    }
                }
            }
        }
        
        if let (width, leftInset, rightInset, maxHeight) = self.validLayout {
            let (_, textFieldHeight) = self.calculateTextFieldMetrics(width: width - leftInset - rightInset, maxHeight: maxHeight)
            let panelHeight = self.panelHeight(textFieldHeight: textFieldHeight)
            if !self.bounds.size.height.isEqual(to: panelHeight) {
                self.updateHeight()
            }
        }
    }
    
    private func applyUpdateSendButtonIcon() {
        if let interfaceState = self.presentationInterfaceState {
            let sendButtonHasApplyIcon = interfaceState.interfaceState.editMessage != nil
            
            if sendButtonHasApplyIcon != self.sendButtonHasApplyIcon {
                self.sendButtonHasApplyIcon = sendButtonHasApplyIcon
                if self.sendButtonHasApplyIcon {
                    self.sendButton.setImage(PresentationResourcesChat.chatInputPanelApplyButtonImage(interfaceState.theme), for: [])
                } else {
                    self.sendButton.setImage(PresentationResourcesChat.chatInputPanelSendButtonImage(interfaceState.theme), for: [])
                }
            }
        }
    }
    
    @objc func editableTextNodeDidChangeSelection(_ editableTextNode: ASEditableTextNode, fromSelectedRange: NSRange, toSelectedRange: NSRange, dueToEditing: Bool) {
        if !dueToEditing && !updatingInputState {
            let inputTextState = self.inputTextState
            self.interfaceInteraction?.updateTextInputState({ _ in return inputTextState })
        }
    }
    
    @objc func editableTextNodeDidBeginEditing(_ editableTextNode: ASEditableTextNode) {
        var activateGifInput = false
        if let presentationInterfaceState = self.presentationInterfaceState {
            if case .media(.gif) = presentationInterfaceState.inputMode {
                activateGifInput = true
            }
        }
        self.interfaceInteraction?.updateInputModeAndDismissedButtonKeyboardMessageId({ state in
            return (.text, state.keyboardButtonsMessage?.id)
        })
        if activateGifInput {
            self.interfaceInteraction?.updateTextInputState { state in
                if state.inputText.isEmpty {
                    return ChatTextInputState(inputText: "@gif ")
                } else {
                    return state
                }
            }
        }
    }
    
    @objc func editableTextNode(_ editableTextNode: ASEditableTextNode, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        self.updateActivity()
        return true
    }
    
    @objc func editableTextNodeShouldPaste(_ editableTextNode: ASEditableTextNode) -> Bool {
        var images: [UIImage] = []
        var text: String?
        
        for item in UIPasteboard.general.items {
            if let image = item[kUTTypeJPEG as String] as? UIImage {
                images.append(image)
            } else if let image = item[kUTTypePNG as String] as? UIImage {
                images.append(image)
            } else if let image = item[kUTTypeGIF as String] as? UIImage {
                images.append(image)
            }
        }
        
        if !images.isEmpty {
            self.pasteImages(images)
            
            return false
        } else {
            return true
        }
        
        /*for (NSDictionary *item in pasteBoard.items) {
            if (item[(__bridge NSString *)kUTTypeJPEG] != nil) {
                [images addObject:item[(__bridge NSString *)kUTTypeJPEG]];
            } else if (item[(__bridge NSString *)kUTTypePNG] != nil) {
                [images addObject:item[(__bridge NSString *)kUTTypePNG]];
            } else if (item[(__bridge NSString *)kUTTypeGIF] != nil) {
                [images addObject:item[(__bridge NSString *)kUTTypeGIF]];
            } else if (item[(__bridge NSString *)kUTTypeURL] != nil) {
                id url = item[(__bridge NSString *)kUTTypeURL];
                if ([url respondsToSelector:@selector(characterAtIndex:)]) {
                    text = url;
                } else if ([url isKindOfClass:[NSURL class]]) {
                    text = ((NSURL *)url).absoluteString;
                }
            }
        }*/
    }
    
    @objc func sendButtonPressed() {
        self.sendMessage()
    }
    
    @objc func attachmentButtonPressed() {
        self.displayAttachmentMenu()
    }
    
    @objc func searchLayoutClearButtonPressed() {
        if let interfaceInteraction = self.interfaceInteraction {
            interfaceInteraction.updateTextInputState { textInputState in
                var mentionQueryRange: Range<String.Index>?
                inner: for (_, type, queryRange) in textInputStateContextQueryRangeAndType(textInputState) {
                    if type == [.contextRequest] {
                        mentionQueryRange = queryRange
                        break inner
                    }
                }
                if let mentionQueryRange = mentionQueryRange, !mentionQueryRange.isEmpty {
                    var inputText = textInputState.inputText
                    inputText.replaceSubrange(mentionQueryRange, with: "")
                    return ChatTextInputState(inputText: inputText)
                } else {
                    return ChatTextInputState(inputText: "")
                }
            }
        }
    }
    
    @objc func textInputBackgroundViewTap(_ recognizer: UITapGestureRecognizer) {
        if case .ended = recognizer.state {
            self.ensureFocused()
        }
    }
    
    var isFocused: Bool {
        return self.textInputNode?.isFirstResponder() ?? false
    }
    
    func ensureUnfocused() {
        self.textInputNode?.resignFirstResponder()
    }
    
    func ensureFocused() {
        if self.textInputNode == nil {
            self.loadTextInputNode()
        }
        
        self.textInputNode?.becomeFirstResponder()
    }
    
    @objc func accessoryItemButtonPressed(_ button: UIView) {
        for (item, currentButton) in self.accessoryItemButtons {
            if currentButton === button {
                switch item {
                    case .stickers:
                        self.interfaceInteraction?.updateInputModeAndDismissedButtonKeyboardMessageId({ state in
                            return (.media(.other), state.interfaceState.messageActionsState.closedButtonKeyboardMessageId)
                        })
                    case .keyboard:
                        self.interfaceInteraction?.updateInputModeAndDismissedButtonKeyboardMessageId({ state in
                            return (.text, state.keyboardButtonsMessage?.id)
                        })
                    case .inputButtons:
                        self.interfaceInteraction?.updateInputModeAndDismissedButtonKeyboardMessageId({ state in
                            return (.inputButtons, nil)
                        })
                    case .messageAutoremoveTimeout:
                        self.interfaceInteraction?.setupMessageAutoremoveTimeout()
                }
                break
            }
        }
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let audioRecordingCancelIndicator = self.audioRecordingCancelIndicator {
            if let result = audioRecordingCancelIndicator.hitTest(point.offsetBy(dx: -audioRecordingCancelIndicator.frame.minX, dy: -audioRecordingCancelIndicator.frame.minY), with: event) {
                return result
            }
        }
        let result = super.hitTest(point, with: event)
        return result
    }
}
