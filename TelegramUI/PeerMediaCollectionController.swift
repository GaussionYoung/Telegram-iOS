import Foundation
import UIKit
import Postbox
import SwiftSignalKit
import Display
import AsyncDisplayKit
import TelegramCore
import SafariServices

public class PeerMediaCollectionController: TelegramController {
    private var containerLayout = ContainerViewLayout()
    
    private let account: Account
    private let peerId: PeerId
    private let messageId: MessageId?
    
    private let peerDisposable = MetaDisposable()
    private let navigationActionDisposable = MetaDisposable()
    
    private let messageIndexDisposable = MetaDisposable()
    
    private let _peerReady = Promise<Bool>()
    private var didSetPeerReady = false
    private let peer = Promise<Peer?>(nil)
    
    private var interfaceState: PeerMediaCollectionInterfaceState
    
    private var rightNavigationButton: PeerMediaCollectionNavigationButton?
    
    private let galleryHiddenMesageAndMediaDisposable = MetaDisposable()
    
    private var controllerInteraction: ChatControllerInteraction?
    private var interfaceInteraction: ChatPanelInterfaceInteraction?
    
    private let messageContextDisposable = MetaDisposable()
    
    private var presentationData: PresentationData
    
    public init(account: Account, peerId: PeerId, messageId: MessageId? = nil) {
        self.account = account
        self.peerId = peerId
        self.messageId = messageId
        
        self.presentationData = account.telegramApplicationContext.currentPresentationData.with { $0 }
        self.interfaceState = PeerMediaCollectionInterfaceState(theme: self.presentationData.theme, strings: self.presentationData.strings)
        
        super.init(account: account, navigationBarTheme: NavigationBarTheme(rootControllerTheme: self.presentationData.theme).withUpdatedSeparatorColor(self.presentationData.theme.rootController.navigationBar.backgroundColor), enableMediaAccessoryPanel: true)
        
        self.title = self.presentationData.strings.SharedMedia_TitleAll
        
        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBar.style.style
        
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Back, style: .plain, target: nil, action: nil)
        
        self.ready.set(.never())
        
        self.scrollToTop = { [weak self] in
            if let strongSelf = self, strongSelf.isNodeLoaded {
                strongSelf.mediaCollectionDisplayNode.historyNode.scrollToEndOfHistory()
            }
        }
        
        let controllerInteraction = ChatControllerInteraction(openMessage: { [weak self] id in
            if let strongSelf = self, strongSelf.isNodeLoaded, let galleryMessage = strongSelf.mediaCollectionDisplayNode.messageForGallery(id) {
                guard let navigationController = strongSelf.navigationController as? NavigationController else {
                    return false
                }
                strongSelf.mediaCollectionDisplayNode.view.endEditing(true)
                return openChatMessage(account: account, message: galleryMessage.message, reverseMessageGalleryOrder: true, navigationController: navigationController, dismissInput: {
                    self?.mediaCollectionDisplayNode.view.endEditing(true)
                }, present: { c, a in
                    self?.present(c, in: .window(.root), with: a)
                }, transitionNode: { messageId, media in
                    if let strongSelf = self {
                        return strongSelf.mediaCollectionDisplayNode.transitionNodeForGallery(messageId: messageId, media: media)
                    }
                    return nil
                }, addToTransitionSurface: { view in
                    if let strongSelf = self {
                        strongSelf.mediaCollectionDisplayNode.view.insertSubview(view, aboveSubview: strongSelf.mediaCollectionDisplayNode.historyNode.view)
                    }
                }, openUrl: { url in
                    if let strongSelf = self {
                        if let applicationContext = strongSelf.account.applicationContext as? TelegramApplicationContext {
                            applicationContext.applicationBindings.openUrl(url)
                        }
                    }
                }, openPeer: { peer, navigation in
                    self?.controllerInteraction?.openPeer(peer.id, navigation, nil)
                }, callPeer: { peerId in
                    self?.controllerInteraction?.callPeer(peerId)
                }, sendSticker: { file in
                    self?.controllerInteraction?.sendSticker(file)
                }, setupTemporaryHiddenMedia: { signal, centralIndex, galleryMedia in
                })
            }
            return false
            }, openSecretMessagePreview: { _ in }, closeSecretMessagePreview: { }, openPeer: { [weak self] id, navigation, _ in
                if let strongSelf = self {
                    if let id = id {
                        (strongSelf.navigationController as? NavigationController)?.pushViewController(ChatController(account: strongSelf.account, chatLocation: .peer(id), messageId: nil))
                    }
                }
            }, openPeerMention: { _ in
            }, openMessageContextMenu: { [weak self] id, _, _ in
                if let strongSelf = self, strongSelf.isNodeLoaded {
                    if let message = strongSelf.mediaCollectionDisplayNode.messageForGallery(id)?.message {
                        let actionSheet = ActionSheetController(presentationTheme: strongSelf.presentationData.theme)
                        actionSheet.setItemGroups([ActionSheetItemGroup(items: [
                                ActionSheetButtonItem(title: strongSelf.presentationData.strings.SharedMedia_ViewInChat, color: .accent, action: { [weak actionSheet] in
                                    actionSheet?.dismissAnimated()
                                    if let strongSelf = self, let navigationController = strongSelf.navigationController as? NavigationController {
                                        navigateToChatController(navigationController: navigationController, account: strongSelf.account, chatLocation: .peer(strongSelf.peerId), messageId: message.id)
                                    }
                                })
                            ]), ActionSheetItemGroup(items: [
                                ActionSheetButtonItem(title: strongSelf.presentationData.strings.Common_Cancel, color: .accent, action: { [weak actionSheet] in
                                    actionSheet?.dismissAnimated()
                            })
                        ])])
                        strongSelf.mediaCollectionDisplayNode.view.endEditing(true)
                        strongSelf.present(actionSheet, in: .window(.root))
                    }
                }
            }, navigateToMessage: { [weak self] fromId, id in
                if let strongSelf = self, strongSelf.isNodeLoaded {
                    if id.peerId == strongSelf.peerId {
                        var fromIndex: MessageIndex?
                        
                        if let message = strongSelf.mediaCollectionDisplayNode.historyNode.messageInCurrentHistoryView(fromId) {
                            fromIndex = MessageIndex(message)
                        }
                        
                        /*if let fromIndex = fromIndex {
                            if let message = strongSelf.mediaCollectionDisplayNode.historyNode.messageInCurrentHistoryView(id) {
                                strongSelf.mediaCollectionDisplayNode.historyNode.scrollToMessage(from: fromIndex, to: MessageIndex(message))
                            } else {
                                strongSelf.messageIndexDisposable.set((strongSelf.account.postbox.messageIndexAtId(id) |> deliverOnMainQueue).start(next: { [weak strongSelf] index in
                                    if let strongSelf = strongSelf, let index = index {
                                        strongSelf.mediaCollectionDisplayNode.historyNode.scrollToMessage(from: fromIndex, to: index)
                                    }
                                }))
                            }
                        }*/
                    } else {
                        (strongSelf.navigationController as? NavigationController)?.pushViewController(ChatController(account: strongSelf.account, chatLocation: .peer(id.peerId), messageId: id))
                    }
                }
            }, clickThroughMessage: { [weak self] in
                self?.view.endEditing(true)
            }, toggleMessagesSelection: { [weak self] ids, value in
                if let strongSelf = self, strongSelf.isNodeLoaded {
                    strongSelf.updateInterfaceState(animated: true, { $0.withToggledSelectedMessages(ids, value: value) })
                }
            }, sendMessage: { _ in
            },sendSticker: { _ in
            }, sendGif: { _ in
            }, requestMessageActionCallback: { _, _, _ in
            }, openUrl: { [weak self] url in
                if let strongSelf = self {
                    if let applicationContext = strongSelf.account.applicationContext as? TelegramApplicationContext {
                        applicationContext.applicationBindings.openUrl(url)
                    }
                }
            }, shareCurrentLocation: {
            }, shareAccountContact: {
            }, sendBotCommand: { _, _ in
            }, openInstantPage: { [weak self] messageId in
                if let strongSelf = self, strongSelf.isNodeLoaded, let navigationController = strongSelf.navigationController as? NavigationController, let message = strongSelf.mediaCollectionDisplayNode.messageForGallery(messageId)?.message {
                    openChatInstantPage(account: strongSelf.account, message: message, navigationController: navigationController)
                }
            }, openHashtag: { _, _ in
            }, updateInputState: { _ in
            }, openMessageShareMenu: { _ in
            }, presentController: { _, _ in
            }, callPeer: { _ in
            }, longTap: { [weak self] content in
                if let strongSelf = self {
                    switch content {
                        case let .url(url):
                            let actionSheet = ActionSheetController(presentationTheme: strongSelf.presentationData.theme)
                            actionSheet.setItemGroups([ActionSheetItemGroup(items: [
                                ActionSheetTextItem(title: url),
                                ActionSheetButtonItem(title: strongSelf.presentationData.strings.Conversation_LinkDialogOpen, color: .accent, action: { [weak actionSheet] in
                                    actionSheet?.dismissAnimated()
                                    if let strongSelf = self {
                                        if let applicationContext = strongSelf.account.applicationContext as? TelegramApplicationContext {
                                            applicationContext.applicationBindings.openUrl(url)
                                        }
                                    }
                                }),
                                ActionSheetButtonItem(title: strongSelf.presentationData.strings.ShareMenu_CopyShareLink, color: .accent, action: { [weak actionSheet] in
                                    actionSheet?.dismissAnimated()
                                    UIPasteboard.general.string = url
                                }),
                                ActionSheetButtonItem(title: strongSelf.presentationData.strings.Conversation_AddToReadingList, color: .accent, action: { [weak actionSheet] in
                                    actionSheet?.dismissAnimated()
                                    if let link = URL(string: url) {
                                        let _ = try? SSReadingList.default()?.addItem(with: link, title: nil, previewText: nil)
                                    }
                                })
                                ]), ActionSheetItemGroup(items: [
                                    ActionSheetButtonItem(title: strongSelf.presentationData.strings.Common_Cancel, color: .accent, action: { [weak actionSheet] in
                                        actionSheet?.dismissAnimated()
                                    })
                                ])])
                            strongSelf.present(actionSheet, in: .window(.root))
                        default:
                            break
                    }
                }
            }, openCheckoutOrReceipt: { _ in
            }, openSearch: { [weak self] in
                self?.activateSearch()
            }, setupReply: { _ in
            }, canSetupReply: {
                return false
        }, automaticMediaDownloadSettings: .none)
        
        self.controllerInteraction = controllerInteraction
        
        self.interfaceInteraction = ChatPanelInterfaceInteraction(setupReplyMessage: { _ in
        }, setupEditMessage: { _ in
        }, beginMessageSelection: { _ in
        }, deleteSelectedMessages: { [weak self] in
            if let strongSelf = self {
                if let messageIds = strongSelf.interfaceState.selectionState?.selectedIds, !messageIds.isEmpty {
                    strongSelf.messageContextDisposable.set((combineLatest(chatDeleteMessagesOptions(postbox: strongSelf.account.postbox, accountPeerId: strongSelf.account.peerId, messageIds: messageIds), strongSelf.peer.get() |> take(1)) |> deliverOnMainQueue).start(next: { options, peer in
                        if let strongSelf = self, let peer = peer, !options.isEmpty {
                            let actionSheet = ActionSheetController(presentationTheme: strongSelf.presentationData.theme)
                            var items: [ActionSheetItem] = []
                            var personalPeerName: String?
                            var isChannel = false
                            if let user = peer as? TelegramUser {
                                personalPeerName = user.compactDisplayTitle
                            } else if let channel = peer as? TelegramChannel, case .broadcast = channel.info {
                                isChannel = true
                            }
                            
                            if options.contains(.globally) {
                                let globalTitle: String
                                if isChannel {
                                    globalTitle = strongSelf.presentationData.strings.Conversation_DeleteMessagesForMe
                                } else if let personalPeerName = personalPeerName {
                                    globalTitle = strongSelf.presentationData.strings.Conversation_DeleteMessagesFor(personalPeerName).0
                                } else {
                                    globalTitle = strongSelf.presentationData.strings.Conversation_DeleteMessagesForEveryone
                                }
                                items.append(ActionSheetButtonItem(title: globalTitle, color: .destructive, action: { [weak actionSheet] in
                                    actionSheet?.dismissAnimated()
                                    if let strongSelf = self {
                                        strongSelf.updateInterfaceState(animated: true, { $0.withoutSelectionState() })
                                        let _ = deleteMessagesInteractively(postbox: strongSelf.account.postbox, messageIds: Array(messageIds), type: .forEveryone).start()
                                    }
                                }))
                            }
                            if options.contains(.locally) {
                                items.append(ActionSheetButtonItem(title: strongSelf.presentationData.strings.Conversation_DeleteMessagesForMe, color: .destructive, action: { [weak actionSheet] in
                                    actionSheet?.dismissAnimated()
                                    if let strongSelf = self {
                                        strongSelf.updateInterfaceState(animated: true, { $0.withoutSelectionState() })
                                        let _ = deleteMessagesInteractively(postbox: strongSelf.account.postbox, messageIds: Array(messageIds), type: .forLocalPeer).start()
                                    }
                                }))
                            }
                            actionSheet.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [
                                ActionSheetButtonItem(title: strongSelf.presentationData.strings.Common_Cancel, color: .accent, action: { [weak actionSheet] in
                                    actionSheet?.dismissAnimated()
                                })
                                ])])
                            strongSelf.present(actionSheet, in: .window(.root))
                        }
                    }))
                }
            }
        }, forwardSelectedMessages: { [weak self] in
            if let strongSelf = self {
                if let forwardMessageIdsSet = strongSelf.interfaceState.selectionState?.selectedIds {
                    let forwardMessageIds = Array(forwardMessageIdsSet).sorted()
                    
                    let controller = PeerSelectionController(account: strongSelf.account)
                    controller.peerSelected = { [weak controller] peerId in
                        if let strongSelf = self, let _ = controller {
                            let _ = (strongSelf.account.postbox.modify({ modifier -> Void in
                                modifier.updatePeerChatInterfaceState(peerId, update: { currentState in
                                    if let currentState = currentState as? ChatInterfaceState {
                                        return currentState.withUpdatedForwardMessageIds(forwardMessageIds)
                                    } else {
                                        return ChatInterfaceState().withUpdatedForwardMessageIds(forwardMessageIds)
                                    }
                                })
                            }) |> deliverOnMainQueue).start(completed: {
                                if let strongSelf = self {
                                    strongSelf.updateInterfaceState(animated: false, { $0.withoutSelectionState() })
                                    
                                    let ready = ValuePromise<Bool>()
                                    
                                    strongSelf.messageContextDisposable.set((ready.get() |> take(1) |> deliverOnMainQueue).start(next: { _ in
                                        if let strongController = controller {
                                            strongController.dismiss()
                                        }
                                    }))
                                    
                                    (strongSelf.navigationController as? NavigationController)?.replaceTopController(ChatController(account: strongSelf.account, chatLocation: .peer(peerId)), animated: false, ready: ready)
                                }
                            })
                        }
                    }
                    strongSelf.present(controller, in: .window(.root))
                }
            }
        }, shareSelectedMessages: { [weak self] in
            if let strongSelf = self, let selectedIds = strongSelf.interfaceState.selectionState?.selectedIds, !selectedIds.isEmpty {
                let _ = (strongSelf.account.postbox.modify { modifier -> [Message] in
                    var messages: [Message] = []
                    for id in selectedIds {
                        if let message = modifier.getMessage(id) {
                            messages.append(message)
                        }
                    }
                    return messages
                    } |> deliverOnMainQueue).start(next: { messages in
                        if let strongSelf = self, !messages.isEmpty {
                            strongSelf.updateInterfaceState(animated: true, {
                                $0.withoutSelectionState()
                            })
                            
                            let shareController = ShareController(account: strongSelf.account, subject: .messages(messages.sorted(by: { lhs, rhs in
                                return MessageIndex(lhs) < MessageIndex(rhs)
                            })), externalShare: true, immediateExternalShare: true)
                            strongSelf.present(shareController, in: .window(.root))
                        }
                    })
            }
        }, updateTextInputState: { _ in
        }, updateInputModeAndDismissedButtonKeyboardMessageId: { _ in
        }, editMessage: {
        }, beginMessageSearch: { _ in
        }, dismissMessageSearch: {
        }, updateMessageSearch: { _ in 
        }, navigateMessageSearch: { _ in
        }, openCalendarSearch: {
        }, toggleMembersSearch: { _ in
        }, navigateToMessage: { _ in
        }, openPeerInfo: {
        }, togglePeerNotifications: {
        }, sendContextResult: { _, _ in
        }, sendBotCommand: { _, _ in
        }, sendBotStart: { _ in
        }, botSwitchChatWithPayload: { _, _ in
        }, beginMediaRecording: { _ in
        }, finishMediaRecording: { _ in 
        }, stopMediaRecording: {
        }, lockMediaRecording: {
        }, deleteRecordedMedia: {
        }, sendRecordedMedia: {
        }, switchMediaRecordingMode: {
        }, setupMessageAutoremoveTimeout: {
        }, sendSticker: { _ in
        }, unblockPeer: {
        }, pinMessage: { _ in
        }, unpinMessage: {
        }, reportPeer: {
        }, dismissReportPeer: {
        }, deleteChat: {
        }, beginCall: {
        }, toggleMessageStickerStarred: { _ in
        }, presentController: { _, _ in
        }, navigateFeed: {
        }, statuses: nil)
        
        self.updateInterfaceState(animated: false, { return $0 })
        
        self.peer.set(account.postbox.peerView(id: peerId) |> map { $0.peers[$0.peerId] })
        
        peerDisposable.set((self.peer.get()
            |> deliverOnMainQueue).start(next: { [weak self] peer in
                if let strongSelf = self {
                    strongSelf.updateInterfaceState(animated: false, { return $0.withUpdatedPeer(peer) })
                    if !strongSelf.didSetPeerReady {
                        strongSelf.didSetPeerReady = true
                        strongSelf._peerReady.set(.single(true))
                    }
                }
            }))
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.messageIndexDisposable.dispose()
        self.navigationActionDisposable.dispose()
        self.galleryHiddenMesageAndMediaDisposable.dispose()
        self.messageContextDisposable.dispose()
    }
    
    var mediaCollectionDisplayNode: PeerMediaCollectionControllerNode {
        get {
            return super.displayNode as! PeerMediaCollectionControllerNode
        }
    }
    
    override public func loadDisplayNode() {
        self.displayNode = PeerMediaCollectionControllerNode(account: self.account, peerId: self.peerId, messageId: self.messageId, controllerInteraction: self.controllerInteraction!, interfaceInteraction: self.interfaceInteraction!, navigationBar: self.navigationBar, requestDeactivateSearch: { [weak self] in
            self?.deactivateSearch()
        })
        
        self.galleryHiddenMesageAndMediaDisposable.set(self.account.telegramApplicationContext.mediaManager.galleryHiddenMediaManager.hiddenIds().start(next: { [weak self] ids in
            if let strongSelf = self, let controllerInteraction = strongSelf.controllerInteraction {
                var messageIdAndMedia: [MessageId: [Media]] = [:]
                
                for id in ids {
                    if case let .chat(messageId, media) = id {
                        messageIdAndMedia[messageId] = [media]
                    }
                }
                
                //if controllerInteraction.hiddenMedia != messageIdAndMedia {
                controllerInteraction.hiddenMedia = messageIdAndMedia
                
                strongSelf.mediaCollectionDisplayNode.historyNode.forEachItemNode { itemNode in
                    if let itemNode = itemNode as? GridMessageItemNode {
                        itemNode.updateHiddenMedia()
                    } else if let itemNode = itemNode as? ListMessageNode {
                        itemNode.updateHiddenMedia()
                    }
                }
                //}
            }
        }))
        
        self.ready.set(combineLatest(self.mediaCollectionDisplayNode.historyNode.historyState.get(), self._peerReady.get()) |> map { $1 })
        
        self.mediaCollectionDisplayNode.requestLayout = { [weak self] transition in
            self?.requestLayout(transition: transition)
        }
        
        self.mediaCollectionDisplayNode.requestUpdateMediaCollectionInterfaceState = { [weak self] animated, f in
            self?.updateInterfaceState(animated: animated, f)
        }
        
        self.displayNodeDidLoad()
    }
    
    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        self.mediaCollectionDisplayNode.historyNode.preloadPages = true
    }
    
    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        
        self.containerLayout = layout
        
        self.mediaCollectionDisplayNode.containerLayoutUpdated(layout, navigationBarHeight: self.navigationHeight, transition: transition,  listViewTransaction: { updateSizeAndInsets in
            self.mediaCollectionDisplayNode.historyNode.updateLayout(transition: transition, updateSizeAndInsets: updateSizeAndInsets)
        })
    }
    
    func updateInterfaceState(animated: Bool = true, _ f: (PeerMediaCollectionInterfaceState) -> PeerMediaCollectionInterfaceState) {
        let updatedInterfaceState = f(self.interfaceState)
        
        if self.isNodeLoaded {
            self.mediaCollectionDisplayNode.updateMediaCollectionInterfaceState(updatedInterfaceState, animated: animated)
        }
        self.interfaceState = updatedInterfaceState
        
        if let button = rightNavigationButtonForPeerMediaCollectionInterfaceState(updatedInterfaceState, currentButton: self.rightNavigationButton, target: self, selector: #selector(self.rightNavigationButtonAction)) {
            if self.rightNavigationButton != button {
                self.navigationItem.setRightBarButton(button.buttonItem, animated: true)
            }
            self.rightNavigationButton = button
        } else if let _ = self.rightNavigationButton {
            self.navigationItem.setRightBarButton(nil, animated: true)
            self.rightNavigationButton = nil
        }
        
        if let controllerInteraction = self.controllerInteraction {
            if updatedInterfaceState.selectionState != controllerInteraction.selectionState {
                let animated = animated || controllerInteraction.selectionState == nil || updatedInterfaceState.selectionState == nil
                controllerInteraction.selectionState = updatedInterfaceState.selectionState
                self.mediaCollectionDisplayNode.historyNode.forEachItemNode { itemNode in
                    if let itemNode = itemNode as? ChatMessageItemView {
                        itemNode.updateSelectionState(animated: animated)
                    } else if let itemNode = itemNode as? GridMessageItemNode {
                        itemNode.updateSelectionState(animated: animated)
                    }
                }
                
                self.mediaCollectionDisplayNode.selectedMessages = updatedInterfaceState.selectionState?.selectedIds
            }
        }
    }
    
    @objc func rightNavigationButtonAction() {
        if let button = self.rightNavigationButton {
            self.navigationButtonAction(button.action)
        }
    }
    
    private func navigationButtonAction(_ action: PeerMediaCollectionNavigationButtonAction) {
        switch action {
            case .cancelMessageSelection:
                self.updateInterfaceState(animated: true, { $0.withoutSelectionState() })
            case .beginMessageSelection:
                self.updateInterfaceState(animated: true, { $0.withSelectionState() })
        }
    }
    
    private func activateSearch() {
        if self.displayNavigationBar {
            if let scrollToTop = self.scrollToTop {
                scrollToTop()
            }
            self.mediaCollectionDisplayNode.activateSearch()
            self.setDisplayNavigationBar(false, transition: .animated(duration: 0.5, curve: .spring))
        }
    }
    
    private func deactivateSearch() {
        if !self.displayNavigationBar {
            self.setDisplayNavigationBar(true, transition: .animated(duration: 0.5, curve: .spring))
            self.mediaCollectionDisplayNode.deactivateSearch()
        }
    }
}
