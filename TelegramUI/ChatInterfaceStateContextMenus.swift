import Foundation
import Postbox
import TelegramCore
import Display
import UIKit
import SwiftSignalKit
import MobileCoreServices

private struct MessageContextMenuData {
    let starStatus: Bool?
    let canReply: Bool
    let canPin: Bool
    let canEdit: Bool
    let resourceStatus: MediaResourceStatus?
}

private let starIconEmpty = UIImage(bundleImageName: "Chat/Context Menu/StarIconEmpty")?.precomposed()
private let starIconFilled = UIImage(bundleImageName: "Chat/Context Menu/StarIconFilled")?.precomposed()

func canReplyInChat(_ chatPresentationInterfaceState: ChatPresentationInterfaceState) -> Bool {
    guard let peer = chatPresentationInterfaceState.peer else {
        return false
    }
    
    var canReply = false
    switch chatPresentationInterfaceState.chatLocation {
        case .peer:
            if let channel = peer as? TelegramChannel {
                if case .member = channel.participationStatus {
                    switch channel.info {
                        case .broadcast:
                            canReply = channel.hasAdminRights([.canPostMessages])
                        case .group:
                            canReply = true
                    }
                }
            } else if let group = peer as? TelegramGroup {
                if case .Member = group.membership {
                    canReply = true
                }
            } else {
                canReply = true
            }
        case .group:
            break
    }
    return canReply
}

func contextMenuForChatPresentationIntefaceState(chatPresentationInterfaceState: ChatPresentationInterfaceState, account: Account, messages: [Message], interfaceInteraction: ChatPanelInterfaceInteraction?, debugStreamSingleVideo: @escaping (MessageId) -> Void) -> Signal<ContextMenuController?, NoError> {
    guard let interfaceInteraction = interfaceInteraction else {
        return .single(nil)
    }
    
    let dataSignal: Signal<MessageContextMenuData, NoError>
    
    var loadStickerSaveStatus: MediaId?
    var loadCopyMediaResource: MediaResource?
    var isAction = false
    if messages.count == 1 {
        for media in messages[0].media {
            if let file = media as? TelegramMediaFile {
                for attribute in file.attributes {
                    if case let .Sticker(_, packInfo, _) = attribute, packInfo != nil {
                        loadStickerSaveStatus = file.fileId
                    }
                }
            } else if let _ = media as? TelegramMediaAction {
                isAction = true
            } else if let image = media as? TelegramMediaImage {
                loadCopyMediaResource = largestImageRepresentation(image.representations)?.resource
            }
        }
    }
    
    var canReply = false
    var canPin = false
    switch chatPresentationInterfaceState.chatLocation {
        case .peer:
            if let channel = messages[0].peers[messages[0].id.peerId] as? TelegramChannel {
                switch channel.info {
                    case .broadcast:
                        canReply = channel.hasAdminRights([.canPostMessages])
                        if !isAction {
                            canPin = channel.hasAdminRights([.canEditMessages])
                        }
                    case .group:
                        canReply = true
                        if !isAction {
                            canPin = channel.hasAdminRights([.canPinMessages])
                        }
                }
            } else {
                canReply = true
            }
        case .group:
            break
    }
    
    var canEdit = false
    if !isAction {
        let message = messages[0]
        
        var hasEditRights = false
        if message.id.peerId.namespace == Namespaces.Peer.SecretChat {
            hasEditRights = false
        } else if let author = message.author, author.id == account.peerId {
            hasEditRights = true
        } else if message.author?.id == message.id.peerId, let peer = message.peers[message.id.peerId] {
            if let peer = peer as? TelegramChannel, case .broadcast = peer.info {
                if peer.hasAdminRights(.canEditMessages) {
                    hasEditRights = true
                }
            }
        }
        
        if hasEditRights {
            var hasUneditableAttributes = false
            for attribute in message.attributes {
                if let _ = attribute as? InlineBotMessageAttribute {
                    hasUneditableAttributes = true
                    break
                }
            }
            if message.forwardInfo != nil {
                hasUneditableAttributes = true
            }
            
            for media in message.media {
                if let file = media as? TelegramMediaFile {
                    if file.isSticker || file.isInstantVideo {
                        hasUneditableAttributes = true
                        break
                    }
                } else if let _ = media as? TelegramMediaContact {
                    hasUneditableAttributes = true
                    break
                }
            }
            
            if !hasUneditableAttributes {
                let timestamp = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
                if message.timestamp >= timestamp - 60 * 60 * 24 * 2 {
                    canEdit = true
                }
            }
        }
    }
    
    var loadStickerSaveStatusSignal: Signal<Bool?, NoError> = .single(nil)
    if loadStickerSaveStatus != nil {
        loadStickerSaveStatusSignal = account.postbox.modify { modifier -> Bool? in
            var starStatus: Bool?
            if let loadStickerSaveStatus = loadStickerSaveStatus {
                if getIsStickerSaved(modifier: modifier, fileId: loadStickerSaveStatus) {
                    starStatus = true
                } else {
                    starStatus = false
                }
            }
            
            return starStatus
        }
    }
    
    var loadResourceStatusSignal: Signal<MediaResourceStatus?, NoError> = .single(nil)
    if let loadCopyMediaResource = loadCopyMediaResource {
        loadResourceStatusSignal = account.postbox.mediaBox.resourceStatus(loadCopyMediaResource)
            |> take(1)
            |> map(Optional.init)
    }
    
    dataSignal = combineLatest(loadStickerSaveStatusSignal, loadResourceStatusSignal)
        |> map { stickerSaveStatus, resourceStatus -> MessageContextMenuData in
        return MessageContextMenuData(starStatus: stickerSaveStatus, canReply: canReply, canPin: canPin, canEdit: canEdit, resourceStatus: resourceStatus)
    }
    
    return dataSignal |> deliverOnMainQueue |> map { data -> ContextMenuController? in
        var actions: [ContextMenuAction] = []
        
        if let starStatus = data.starStatus, let image = starStatus ? starIconFilled : starIconEmpty {
            actions.append(ContextMenuAction(content: .icon(image), action: {
                interfaceInteraction.toggleMessageStickerStarred(messages[0].id)
            }))
        }
        
        if data.canReply {
            actions.append(ContextMenuAction(content: .text(chatPresentationInterfaceState.strings.Conversation_ContextMenuReply), action: {
                interfaceInteraction.setupReplyMessage(messages[0].id)
            }))
        }
        
        if data.canEdit {
            actions.append(ContextMenuAction(content: .text(chatPresentationInterfaceState.strings.Conversation_Edit), action: {
                interfaceInteraction.setupEditMessage(messages[0].id)
            }))
        }
        
        let resourceAvailable: Bool
        if let resourceStatus = data.resourceStatus, case .Local = resourceStatus {
            resourceAvailable = true
        } else {
            resourceAvailable = false
        }
        
        if !messages[0].text.isEmpty || resourceAvailable {
            let message = messages[0]
            actions.append(ContextMenuAction(content: .text(chatPresentationInterfaceState.strings.Conversation_ContextMenuCopy), action: {
                if resourceAvailable {
                    for media in message.media {
                        if let image = media as? TelegramMediaImage, let largest = largestImageRepresentation(image.representations) {
                            let _ = (account.postbox.mediaBox.resourceData(largest.resource, option: .incremental(waitUntilFetchStatus: false))
                                |> take(1)
                                |> deliverOnMainQueue).start(next: { data in
                                    if data.complete, let imageData = try? Data(contentsOf: URL(fileURLWithPath: data.path)) {
                                        if let image = UIImage(data: imageData) {
                                            if !message.text.isEmpty {
                                                UIPasteboard.general.items = [
                                                    [kUTTypeUTF8PlainText as String: message.text],
                                                    [kUTTypePNG as String: image]
                                                ]
                                            } else {
                                                UIPasteboard.general.image = image
                                            }
                                        } else {
                                            UIPasteboard.general.string = message.text
                                        }
                                    } else {
                                        UIPasteboard.general.string = message.text
                                    }
                                })
                        }
                    }
                } else {
                    UIPasteboard.general.string = message.text
                }
            }))
        }
        
        if data.canPin {
            if chatPresentationInterfaceState.pinnedMessage?.id != messages[0].id {
                actions.append(ContextMenuAction(content: .text(chatPresentationInterfaceState.strings.Conversation_Pin), action: {
                    interfaceInteraction.pinMessage(messages[0].id)
                }))
            } else {
                actions.append(ContextMenuAction(content: .text(chatPresentationInterfaceState.strings.Conversation_Unpin), action: {
                    interfaceInteraction.unpinMessage()
                }))
            }
        }
        
        if messages.count == 1 {
            let message = messages[0]
            
            for media in message.media {
                if let file = media as? TelegramMediaFile {
                    if file.isVideo {
                        if file.isAnimated {
                            actions.append(ContextMenuAction(content: .text(chatPresentationInterfaceState.strings.Conversation_LinkDialogSave), action: {
                                let _ = addSavedGif(postbox: account.postbox, file: file).start()
                            }))
                        } else if !GlobalExperimentalSettings.isAppStoreBuild {
                            actions.append(ContextMenuAction(content: .text("Stream"), action: {
                                debugStreamSingleVideo(message.id)
                            }))
                        }
                        break
                    }
                }
            }
        }
    actions.append(ContextMenuAction(content: .text(chatPresentationInterfaceState.strings.Conversation_ContextMenuMore), action: {
            interfaceInteraction.beginMessageSelection(messages.map { $0.id })
        }))
        
        if !actions.isEmpty {
            let contextMenuController = ContextMenuController(actions: actions)
            return contextMenuController
        } else {
            return nil
        }
    }
}

struct ChatDeleteMessagesOptions: OptionSet {
    var rawValue: Int32
    
    init(rawValue: Int32) {
        self.rawValue = rawValue
    }
    
    init() {
        self.rawValue = 0
    }
    
    static let locally = ChatDeleteMessagesOptions(rawValue: 1 << 0)
    static let globally = ChatDeleteMessagesOptions(rawValue: 1 << 1)
}

func chatDeleteMessagesOptions(postbox: Postbox, accountPeerId: PeerId, messageIds: Set<MessageId>) -> Signal<ChatDeleteMessagesOptions, NoError> {
    return postbox.modify { modifier -> ChatDeleteMessagesOptions in
        var optionsMap: [MessageId: ChatDeleteMessagesOptions] = [:]
        for id in messageIds {
            if id.peerId == accountPeerId {
                optionsMap[id] = .locally
            } else if let peer = modifier.getPeer(id.peerId), let message = modifier.getMessage(id) {
                if let channel = peer as? TelegramChannel {
                    var options: ChatDeleteMessagesOptions = []
                    if !message.flags.contains(.Incoming) {
                        options.insert(.globally)
                    } else {
                        if channel.hasAdminRights([.canDeleteMessages]) {
                            options.insert(.globally)
                        }
                    }
                    optionsMap[message.id] = options
                } else if let group = peer as? TelegramGroup {
                    var options: ChatDeleteMessagesOptions = []
                    options.insert(.locally)
                    if !message.flags.contains(.Incoming) {
                        options.insert(.globally)
                    } else {
                        switch group.role {
                            case .creator, .admin:
                                options.insert(.globally)
                            case .member:
                                break
                        }
                    }
                    optionsMap[message.id] = options
                } else if let _ = peer as? TelegramUser {
                    var options: ChatDeleteMessagesOptions = []
                    options.insert(.locally)
                    if !message.flags.contains(.Incoming) {
                        options.insert(.globally)
                    }
                    optionsMap[message.id] = options
                } else if let _ = peer as? TelegramSecretChat {
                    var options: ChatDeleteMessagesOptions = []
                    options.insert(.globally)
                    optionsMap[message.id] = options
                } else {
                    assertionFailure()
                }
            } else {
                optionsMap[id] = [.locally]
            }
        }
        
        if !optionsMap.isEmpty {
            var reducedOptions = optionsMap.values.first!
            for value in optionsMap.values {
                reducedOptions.formIntersection(value)
            }
            return reducedOptions
        } else {
            return []
        }
    }
}
