import Foundation
import UIKit
import Postbox
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore

public enum ChatMessageItemContent: Sequence {
    case message(message: Message, read: Bool, selection: ChatHistoryMessageSelection)
    case group(messages: [(Message, Bool, ChatHistoryMessageSelection)])
    
    func effectivelyIncoming(_ accountPeerId: PeerId) -> Bool {
        switch self {
            case let .message(message, _, _):
                return message.effectivelyIncoming(accountPeerId)
            case let .group(messages):
                return messages[0].0.effectivelyIncoming(accountPeerId)
        }
    }
    
    var index: MessageIndex {
        switch self {
            case let .message(message, _, _):
                return MessageIndex(message)
            case let .group(messages):
                return MessageIndex(messages[0].0)
        }
    }
    
    var firstMessage: Message {
        switch self {
            case let .message(message, _, _):
                return message
            case let .group(messages):
                return messages[0].0
        }
    }
    
    public func makeIterator() -> AnyIterator<Message> {
        var index = 0
        return AnyIterator { () -> Message? in
            switch self {
                case let .message(message, _, _):
                    if index == 0 {
                        index += 1
                        return message
                    } else {
                        index += 1
                        return nil
                    }
                case let .group(messages):
                    if index < messages.count {
                        let currentIndex = index
                        index += 1
                        return messages[currentIndex].0
                    } else {
                        return nil
                    }
            }
        }
    }
}

private func mediaIsNotMergeable(_ media: Media) -> Bool {
    if let file = media as? TelegramMediaFile, file.isSticker {
        return true
    }
    if let _ = media as? TelegramMediaAction {
        return true
    }
    if let _ = media as? TelegramMediaExpiredContent {
        return true
    }
    
    return false
}

private func messagesShouldBeMerged(accountPeerId: PeerId, _ lhs: Message, _ rhs: Message) -> Bool {
    var lhsEffectiveAuthor: Peer? = lhs.author
    var rhsEffectiveAuthor: Peer? = rhs.author
    if lhs.id.peerId == accountPeerId {
        if let forwardInfo = lhs.forwardInfo {
            lhsEffectiveAuthor = forwardInfo.author
        }
    }
    if rhs.id.peerId == accountPeerId {
        if let forwardInfo = rhs.forwardInfo {
            rhsEffectiveAuthor = forwardInfo.author
        }
    }
    
    if abs(lhs.timestamp - rhs.timestamp) < Int32(5 * 60) && lhsEffectiveAuthor?.id == rhsEffectiveAuthor?.id {
        for media in lhs.media {
            if mediaIsNotMergeable(media) {
                return false
            }
        }
        for media in rhs.media {
            if mediaIsNotMergeable(media) {
                return false
            }
        }
        for attribute in lhs.attributes {
            if let attribute = attribute as? ReplyMarkupMessageAttribute {
                if attribute.flags.contains(.inline) && !attribute.rows.isEmpty {
                    return false
                }
                break
            }
        }
        
        return true
    }
    
    return false
}

func chatItemsHaveCommonDateHeader(_ lhs: ListViewItem, _ rhs: ListViewItem?)  -> Bool{
    let lhsHeader: ChatMessageDateHeader?
    let rhsHeader: ChatMessageDateHeader?
    if let lhs = lhs as? ChatMessageItem {
        lhsHeader = lhs.header
    } else if let _ = lhs as? ChatHoleItem {
        //lhsHeader = lhs.header
        lhsHeader = nil
    } else if let lhs = lhs as? ChatUnreadItem {
        lhsHeader = lhs.header
    } else {
        lhsHeader = nil
    }
    if let rhs = rhs {
        if let rhs = rhs as? ChatMessageItem {
            rhsHeader = rhs.header
        } else if let _ = rhs as? ChatHoleItem {
            //rhsHeader = rhs.header
            rhsHeader = nil
        } else if let rhs = rhs as? ChatUnreadItem {
            rhsHeader = rhs.header
        } else {
            rhsHeader = nil
        }
    } else {
        rhsHeader = nil
    }
    if let lhsHeader = lhsHeader, let rhsHeader = rhsHeader {
        return lhsHeader.id == rhsHeader.id
    } else {
        return false
    }
}

public final class ChatMessageItem: ListViewItem, CustomStringConvertible {
    let presentationData: ChatPresentationData
    let account: Account
    let chatLocation: ChatLocation
    let controllerInteraction: ChatControllerInteraction
    let content: ChatMessageItemContent
    let disableDate: Bool
    let effectiveAuthorId: PeerId?
    
    public let accessoryItem: ListViewAccessoryItem?
    let header: ChatMessageDateHeader
    
    var message: Message {
        switch self.content {
            case let .message(message, _, _):
                return message
            case let .group(messages):
                return messages[0].0
        }
    }
    
    var read: Bool {
        switch self.content {
            case let .message(_, read, _):
                return read
            case let .group(messages):
                return messages[0].1
        }
    }
    
    public init(presentationData: ChatPresentationData, account: Account, chatLocation: ChatLocation, controllerInteraction: ChatControllerInteraction, content: ChatMessageItemContent, disableDate: Bool = false) {
        self.presentationData = presentationData
        self.account = account
        self.chatLocation = chatLocation
        self.controllerInteraction = controllerInteraction
        self.content = content
        self.disableDate = disableDate
        
        var accessoryItem: ListViewAccessoryItem?
        let incoming = content.effectivelyIncoming(self.account.peerId)
        
        var effectiveAuthor: Peer?
        let displayAuthorInfo: Bool
        
        switch chatLocation {
            case let .peer(peerId):
                if peerId == account.peerId {
                    if let forwardInfo = content.firstMessage.forwardInfo {
                        effectiveAuthor = forwardInfo.author
                    }
                    displayAuthorInfo = incoming && effectiveAuthor != nil
                } else {
                    effectiveAuthor = content.firstMessage.author
                    displayAuthorInfo = incoming && peerId.isGroupOrChannel && effectiveAuthor != nil
                }
            case .group:
                effectiveAuthor = content.firstMessage.author
                displayAuthorInfo = incoming && effectiveAuthor != nil
        }
        
        self.effectiveAuthorId = effectiveAuthor?.id
        
        self.header = ChatMessageDateHeader(timestamp: content.index.timestamp, theme: presentationData.theme, strings: presentationData.strings)
        
        if displayAuthorInfo {
            let message = content.firstMessage
            var hasActionMedia = false
            for media in message.media {
                if media is TelegramMediaAction {
                    hasActionMedia = true
                    break
                }
            }
            var isBroadcastChannel = false
            if case .peer = chatLocation {
                if let peer = message.peers[message.id.peerId] as? TelegramChannel, case .broadcast = peer.info {
                    isBroadcastChannel = true
                }
            }
            if !hasActionMedia && !isBroadcastChannel {
                if let effectiveAuthor = effectiveAuthor {
                    accessoryItem = ChatMessageAvatarAccessoryItem(account: account, peerId: effectiveAuthor.id, peer: effectiveAuthor, messageTimestamp: content.index.timestamp)
                }
            }
        }
        self.accessoryItem = accessoryItem
    }
    
    public func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, () -> Void)) -> Void) {
        var viewClassName: AnyClass = ChatMessageBubbleItemNode.self
        
        loop: for media in message.media {
            if let telegramFile = media as? TelegramMediaFile {
                for attribute in telegramFile.attributes {
                    switch attribute {
                        case .Sticker:
                            viewClassName = ChatMessageStickerItemNode.self
                            break loop
                        case let .Video(_, _, flags):
                            if flags.contains(.instantRoundVideo) {
                                viewClassName = ChatMessageInstantVideoItemNode.self
                                break loop
                            }
                        default:
                            break
                    }
                }
            } else if let action = media as? TelegramMediaAction {
                if case .phoneCall = action.action {
                    viewClassName = ChatMessageBubbleItemNode.self
                } else {
                    viewClassName = ChatMessageActionItemNode.self
                }
            } else if let _ = media as? TelegramMediaExpiredContent {
                viewClassName = ChatMessageActionItemNode.self
            }
        }
        
        let configure = {
            let node = (viewClassName as! ChatMessageItemView.Type).init()
            node.setupItem(self)
            
            let nodeLayout = node.asyncLayout()
            let (top, bottom, dateAtBottom) = self.mergedWithItems(top: previousItem, bottom: nextItem)
            let (layout, apply) = nodeLayout(self, params, top, bottom, dateAtBottom && !self.disableDate)
            
            node.updateSelectionState(animated: false)
            node.updateHighlightedState(animated: false)
            
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            
            completion(node, {
                return (nil, { apply(.None) })
            })
        }
        if Thread.isMainThread {
            async {
                configure()
            }
        } else {
            configure()
        }
    }
    
    final func mergedWithItems(top: ListViewItem?, bottom: ListViewItem?) -> (top: Bool, bottom: Bool, dateAtBottom: Bool) {
        var mergedTop = false
        var mergedBottom = false
        var dateAtBottom = false
        if let top = top as? ChatMessageItem {
            if top.header.id != self.header.id {
                mergedBottom = false
            } else {
                mergedBottom = messagesShouldBeMerged(accountPeerId: self.account.peerId, message, top.message)
            }
        }
        if let bottom = bottom as? ChatMessageItem {
            if bottom.header.id != self.header.id {
                mergedTop = false
                dateAtBottom = true
            } else {
                mergedTop = messagesShouldBeMerged(accountPeerId: self.account.peerId, bottom.message, message)
            }
        } else if let bottom = bottom as? ChatUnreadItem {
            if bottom.header.id != self.header.id {
                dateAtBottom = true
            }
        } else if let bottom = bottom as? ChatHoleItem {
            //if bottom.header.id != self.header.id {
                dateAtBottom = true
            //}
        } else {
            dateAtBottom = true
        }
        
        return (mergedTop, mergedBottom, dateAtBottom)
    }
    
    public func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping () -> Void) -> Void) {
        if let node = node as? ChatMessageItemView {
            Queue.mainQueue().async {
                node.setupItem(self)
                
                let nodeLayout = node.asyncLayout()
                
                async {
                    let (top, bottom, dateAtBottom) = self.mergedWithItems(top: previousItem, bottom: nextItem)
                    
                    let (layout, apply) = nodeLayout(self, params, top, bottom, dateAtBottom && !self.disableDate)
                    Queue.mainQueue().async {
                        completion(layout, {
                            apply(animation)
                            node.updateSelectionState(animated: false)
                            node.updateHighlightedState(animated: false)
                        })
                    }
                }
            }
        }
    }
    
    public var description: String {
        return "(ChatMessageItem id: \(self.message.id), text: \"\(self.message.text)\")"
    }
    
    
}
