import Foundation
import AsyncDisplayKit
import Display
import Postbox
import TelegramCore
import SwiftSignalKit

public final class ChatMessageNotificationItem: NotificationItem {
    let account: Account
    let strings: PresentationStrings
    let message: Message
    let tapAction: () -> Bool
    let expandAction: (@escaping () -> (ASDisplayNode?, () -> Void)) -> Void
    
    public var groupingKey: AnyHashable? {
        return message.id.peerId
    }
    
    public init(account: Account, strings: PresentationStrings, message: Message, tapAction: @escaping () -> Bool, expandAction: @escaping (() -> (ASDisplayNode?, () -> Void)) -> Void) {
        self.account = account
        self.strings = strings
        self.message = message
        self.tapAction = tapAction
        self.expandAction = expandAction
    }
    
    public func node() -> NotificationItemNode {
        let node = ChatMessageNotificationItemNode()
        node.setupItem(self)
        return node
    }
    
    public func tapped(_ take: @escaping () -> (ASDisplayNode?, () -> Void)) {
        if self.tapAction() {
            self.expandAction(take)
        }
    }
    
    public func canBeExpanded() -> Bool {
        return true
    }
    
    public func expand(_ take: @escaping () -> (ASDisplayNode?, () -> Void)) {
        self.expandAction(take)
    }
}

private let avatarFont: UIFont = UIFont(name: "ArialRoundedMTBold", size: 24.0)!

final class ChatMessageNotificationItemNode: NotificationItemNode {
    private var item: ChatMessageNotificationItem?
    
    private let avatarNode: AvatarNode
    private let titleNode: TextNode
    private let textNode: TextNode
    private let imageNode: TransformImageNode
    
    private var titleAttributedText: NSAttributedString?
    private var textAttributedText: NSAttributedString?
    
    private var validLayout: CGFloat?
    
    override init() {
        self.avatarNode = AvatarNode(font: avatarFont)
        
        self.titleNode = TextNode()
        self.titleNode.isLayerBacked = true
        
        self.textNode = TextNode()
        self.textNode.isLayerBacked = true
        
        self.imageNode = TransformImageNode()
        
        super.init()
        
        self.addSubnode(self.avatarNode)
        self.addSubnode(self.titleNode)
        self.addSubnode(self.textNode)
        self.addSubnode(self.imageNode)
    }
    
    func setupItem(_ item: ChatMessageNotificationItem) {
        self.item = item
        let presentationData = item.account.telegramApplicationContext.currentPresentationData.with { $0 }
        
        if let peer = messageMainPeer(item.message) {
            self.avatarNode.setPeer(account: item.account, peer: peer)
            
            if let channel = peer as? TelegramChannel, case .broadcast = channel.info {
                self.titleAttributedText = NSAttributedString(string: peer.displayTitle, font: Font.semibold(16.0), textColor: presentationData.theme.inAppNotification.primaryTextColor)
            } else if let author = item.message.author, author.id != peer.id {
                self.titleAttributedText = NSAttributedString(string: author.displayTitle + "@" + peer.displayTitle, font: Font.semibold(16.0), textColor: presentationData.theme.inAppNotification.primaryTextColor)
            } else {
                self.titleAttributedText = NSAttributedString(string: peer.displayTitle, font: Font.semibold(16.0), textColor: presentationData.theme.inAppNotification.primaryTextColor)
            }
        }
        
        var updatedMedia: Media?
        var imageDimensions: CGSize?
        for media in item.message.media {
            if let image = media as? TelegramMediaImage {
                updatedMedia = image
                if let representation = largestRepresentationForPhoto(image) {
                    imageDimensions = representation.dimensions
                }
                break
            } else if let file = media as? TelegramMediaFile {
                updatedMedia = file
                if let representation = largestImageRepresentation(file.previewRepresentations) {
                    imageDimensions = representation.dimensions
                }
                break
            }
        }
        
        let imageNodeLayout = self.imageNode.asyncLayout()
        var applyImage: (() -> Void)?
        if let imageDimensions = imageDimensions {
            let boundingSize = CGSize(width: 55.0, height: 55.0)
            applyImage = imageNodeLayout(TransformImageArguments(corners: ImageCorners(radius: 6.0), imageSize: imageDimensions.aspectFilled(boundingSize), boundingSize: boundingSize, intrinsicInsets: UIEdgeInsets()))
        }
        
        var updateImageSignal: Signal<(TransformImageArguments) -> DrawingContext?, NoError>?
        if let updatedMedia = updatedMedia, imageDimensions != nil {
            if let image = updatedMedia as? TelegramMediaImage {
                updateImageSignal = mediaGridMessagePhoto(account: item.account, photo: image)
            } else if let file = updatedMedia as? TelegramMediaFile {
                if file.isSticker {
                    updateImageSignal = chatMessageSticker(account: item.account, file: file, small: true, fetched: true)
                } else if file.isVideo {
                    updateImageSignal = mediaGridMessageVideo(postbox: item.account.postbox, video: file)
                }
            }
        }
        
        let messageText = descriptionStringForMessage(item.message, strings: item.strings, accountPeerId: item.account.peerId)
        
        if let applyImage = applyImage {
            applyImage()
            self.imageNode.isHidden = false
        } else {
            self.imageNode.isHidden = true
        }
        
        if let updateImageSignal = updateImageSignal {
            self.imageNode.setSignal(updateImageSignal)
        }
        
        self.textAttributedText = NSAttributedString(string: messageText, font: Font.regular(16.0), textColor: presentationData.theme.inAppNotification.primaryTextColor)
        
        if let validLayout = self.validLayout {
            let _ = self.updateLayout(width: validLayout, transition: .immediate)
        }
    }
    
    override func updateLayout(width: CGFloat, transition: ContainedViewLayoutTransition) -> CGFloat {
        self.validLayout = width
        
        let panelHeight: CGFloat = 74.0
        let leftInset: CGFloat = 77.0
        var rightInset: CGFloat = 8.0
        
        if !self.imageNode.isHidden {
            rightInset += 55.0 + 8.0
        }
        
        transition.updateFrame(node: self.avatarNode, frame: CGRect(origin: CGPoint(x: 10.0, y: 10.0), size: CGSize(width: 54.0, height: 54.0)))
        
        let makeTitleLayout = TextNode.asyncLayout(self.titleNode)
        let (titleLayout, titleApply) = makeTitleLayout(TextNodeLayoutArguments(attributedString: self.titleAttributedText, backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: width - leftInset - rightInset, height: CGFloat.greatestFiniteMagnitude), alignment: .left, lineSpacing: 0.0, cutout: nil, insets: UIEdgeInsets()))
        let _ = titleApply()
        
        let makeTextLayout = TextNode.asyncLayout(self.textNode)
        let (textLayout, textApply) = makeTextLayout(TextNodeLayoutArguments(attributedString: self.textAttributedText, backgroundColor: nil, maximumNumberOfLines: 2, truncationType: .end, constrainedSize: CGSize(width: width - leftInset - rightInset, height: CGFloat.greatestFiniteMagnitude), alignment: .left, lineSpacing: 0.0, cutout: nil, insets: UIEdgeInsets()))
        let _ = titleApply()
        let _ = textApply()
        
        let textSpacing: CGFloat = 1.0
        
        let titleFrame = CGRect(origin: CGPoint(x: leftInset, y: 1.0 + floor((panelHeight - textLayout.size.height - titleLayout.size.height - textSpacing) / 2.0)), size: titleLayout.size)
        transition.updateFrame(node: self.titleNode, frame: titleFrame)
        
        transition.updateFrame(node: self.textNode, frame: CGRect(origin: CGPoint(x: leftInset, y: titleFrame.maxY + textSpacing), size: textLayout.size))
        
        transition.updateFrame(node: self.imageNode, frame: CGRect(origin: CGPoint(x: width - 9.0 - 55.0, y: 9.0), size: CGSize(width: 55.0, height: 55.0)))
        
        return 74.0
    }
}
