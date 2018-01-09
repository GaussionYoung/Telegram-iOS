import Foundation
import AsyncDisplayKit
import Display
import Postbox
import TelegramCore
import SwiftSignalKit

private struct CallListNodeListViewTransition {
    let callListView: CallListNodeView
    let deleteItems: [ListViewDeleteItem]
    let insertItems: [ListViewInsertItem]
    let updateItems: [ListViewUpdateItem]
    let options: ListViewDeleteAndInsertOptions
    let scrollToItem: ListViewScrollToItem?
    let stationaryItemRange: (Int, Int)?
}

private extension CallListViewEntry {
    var lowestIndex: MessageIndex {
        switch self {
            case let .hole(index):
                return index
            case let .message(_, messages):
                var lowest = MessageIndex(messages[0])
                for i in 1 ..< messages.count {
                    let index = MessageIndex(messages[i])
                    if index < lowest {
                        lowest = index
                    }
                }
                return lowest
        }
    }
    
    var highestIndex: MessageIndex {
        switch self {
        case let .hole(index):
            return index
        case let .message(_, messages):
            var highest = MessageIndex(messages[0])
            for i in 1 ..< messages.count {
                let index = MessageIndex(messages[i])
                if index > highest {
                    highest = index
                }
            }
            return highest
        }
    }
}

final class CallListNodeInteraction {
    let setMessageIdWithRevealedOptions: (MessageId?, MessageId?) -> Void
    let call: (PeerId) -> Void
    let openInfo: (PeerId) -> Void
    let delete: ([MessageId]) -> Void
    let updateShowCallsTab: (Bool) -> Void
    
    init(setMessageIdWithRevealedOptions: @escaping (MessageId?, MessageId?) -> Void, call: @escaping (PeerId) -> Void, openInfo: @escaping (PeerId) -> Void, delete: @escaping ([MessageId]) -> Void, updateShowCallsTab: @escaping (Bool) -> Void) {
        self.setMessageIdWithRevealedOptions = setMessageIdWithRevealedOptions
        self.call = call
        self.openInfo = openInfo
        self.delete = delete
        self.updateShowCallsTab = updateShowCallsTab
    }
}

struct CallListNodeState: Equatable {
    let theme: PresentationTheme
    let strings: PresentationStrings
    let editing: Bool
    let messageIdWithRevealedOptions: MessageId?
    
    func withUpdatedPresentationData(theme: PresentationTheme, strings: PresentationStrings) -> CallListNodeState {
        return CallListNodeState(theme: theme, strings: strings, editing: self.editing, messageIdWithRevealedOptions: self.messageIdWithRevealedOptions)
    }
    
    func withUpdatedEditing(_ editing: Bool) -> CallListNodeState {
        return CallListNodeState(theme: self.theme, strings: self.strings, editing: editing, messageIdWithRevealedOptions: self.messageIdWithRevealedOptions)
    }
    
    func withUpdatedMessageIdWithRevealedOptions(_ messageIdWithRevealedOptions: MessageId?) -> CallListNodeState {
        return CallListNodeState(theme: self.theme, strings: self.strings, editing: self.editing, messageIdWithRevealedOptions: messageIdWithRevealedOptions)
    }
    
    static func ==(lhs: CallListNodeState, rhs: CallListNodeState) -> Bool {
        if lhs.theme !== rhs.theme {
            return false
        }
        if lhs.strings !== rhs.strings {
            return false
        }
        if lhs.editing != rhs.editing {
            return false
        }
        if lhs.messageIdWithRevealedOptions != rhs.messageIdWithRevealedOptions {
            return false
        }
        return true
    }
}

private func mappedInsertEntries(account: Account, showSettings: Bool, nodeInteraction: CallListNodeInteraction, entries: [CallListNodeViewTransitionInsertEntry]) -> [ListViewInsertItem] {
    return entries.map { entry -> ListViewInsertItem in
        switch entry.entry {
            case let .displayTab(theme, text, value):
                return ListViewInsertItem(index: entry.index, previousIndex: entry.previousIndex, item: ItemListSwitchItem(theme: theme, title: text, value: value, enabled: true, sectionId: 0, style: .blocks, updated: { value in
                    nodeInteraction.updateShowCallsTab(value)
                }), directionHint: entry.directionHint)
            case let .displayTabInfo(theme, text):
                return ListViewInsertItem(index: entry.index, previousIndex: entry.previousIndex, item: ItemListTextItem(theme: theme, text: .plain(text), sectionId: 0), directionHint: entry.directionHint)
            case let .messageEntry(topMessage, messages, theme, strings, editing, hasActiveRevealControls):
                return ListViewInsertItem(index: entry.index, previousIndex: entry.previousIndex, item:  CallListCallItem(theme: theme, strings: strings, account: account, style: showSettings ? .blocks : .plain, topMessage: topMessage, messages: messages, editing: editing, revealed: hasActiveRevealControls, interaction: nodeInteraction), directionHint: entry.directionHint)
            case let .holeEntry(_, theme):
                return ListViewInsertItem(index: entry.index, previousIndex: entry.previousIndex, item: ChatListHoleItem(theme: theme), directionHint: entry.directionHint)
        }
    }
}

private func mappedUpdateEntries(account: Account, showSettings: Bool, nodeInteraction: CallListNodeInteraction, entries: [CallListNodeViewTransitionUpdateEntry]) -> [ListViewUpdateItem] {
    return entries.map { entry -> ListViewUpdateItem in
        switch entry.entry {
            case let .displayTab(theme, text, value):
                return ListViewUpdateItem(index: entry.index, previousIndex: entry.previousIndex, item: ItemListSwitchItem(theme: theme, title: text, value: value, enabled: true, sectionId: 0, style: .blocks, updated: { value in
                    nodeInteraction.updateShowCallsTab(value)
                }), directionHint: entry.directionHint)
            case let .displayTabInfo(theme, text):
                return ListViewUpdateItem(index: entry.index, previousIndex: entry.previousIndex, item: ItemListTextItem(theme: theme, text: .plain(text), sectionId: 0), directionHint: entry.directionHint)
            case let .messageEntry(topMessage, messages, theme, strings, editing, hasActiveRevealControls):
                return ListViewUpdateItem(index: entry.index, previousIndex: entry.previousIndex, item: CallListCallItem(theme: theme, strings: strings, account: account, style: showSettings ? .blocks : .plain, topMessage: topMessage, messages: messages, editing: editing, revealed: hasActiveRevealControls, interaction: nodeInteraction), directionHint: entry.directionHint)
            case let .holeEntry(_, theme):
                return ListViewUpdateItem(index: entry.index, previousIndex: entry.previousIndex, item: ChatListHoleItem(theme: theme), directionHint: entry.directionHint)
        }
    }
}

private func mappedCallListNodeViewListTransition(account: Account, showSettings: Bool, nodeInteraction: CallListNodeInteraction, transition: CallListNodeViewTransition) -> CallListNodeListViewTransition {
    return CallListNodeListViewTransition(callListView: transition.callListView, deleteItems: transition.deleteItems, insertItems: mappedInsertEntries(account: account, showSettings: showSettings, nodeInteraction: nodeInteraction, entries: transition.insertEntries), updateItems: mappedUpdateEntries(account: account, showSettings: showSettings, nodeInteraction: nodeInteraction, entries: transition.updateEntries), options: transition.options, scrollToItem: transition.scrollToItem, stationaryItemRange: transition.stationaryItemRange)
}

private final class CallListOpaqueTransactionState {
    let callListView: CallListNodeView
    
    init(callListView: CallListNodeView) {
        self.callListView = callListView
    }
}

final class CallListControllerNode: ASDisplayNode {
    private let account: Account
    private let mode: CallListControllerMode
    private var presentationData: PresentationData
    
    private var containerLayout: (ContainerViewLayout, CGFloat)?
    
    private let _ready = ValuePromise<Bool>()
    private var didSetReady = false
    var ready: Signal<Bool, NoError> {
        return _ready.get()
    }
    
    var peerSelected: ((PeerId) -> Void)?
    var activateSearch: (() -> Void)?
    var deletePeerChat: ((PeerId) -> Void)?
    
    private let viewProcessingQueue = Queue()
    private var callListView: CallListNodeView?
    
    private var dequeuedInitialTransitionOnLayout = false
    private var enqueuedTransition: (CallListNodeListViewTransition, () -> Void)?
    
    private var currentState: CallListNodeState
    private let statePromise: ValuePromise<CallListNodeState>
    
    private var currentLocationAndType = CallListNodeLocationAndType(location: .initial(count: 50), type: .all)
    private let callListLocationAndType = ValuePromise<CallListNodeLocationAndType>()
    private let callListDisposable = MetaDisposable()
    
    private let listNode: ListView
    
    private let call: (PeerId) -> Void
    private let openInfo: (PeerId) -> Void
    private let emptyStateUpdated: (Bool) -> Void
    
    init(account: Account, mode: CallListControllerMode, presentationData: PresentationData, call: @escaping (PeerId) -> Void, openInfo: @escaping (PeerId) -> Void, emptyStateUpdated: @escaping (Bool) -> Void) {
        self.account = account
        self.mode = mode
        self.presentationData = presentationData
        self.call = call
        self.openInfo = openInfo
        self.emptyStateUpdated = emptyStateUpdated
        
        self.currentState = CallListNodeState(theme: presentationData.theme, strings: presentationData.strings, editing: false, messageIdWithRevealedOptions: nil)
        self.statePromise = ValuePromise(self.currentState, ignoreRepeated: true)
        
        self.listNode = ListView()
        
        super.init()
        
        self.setViewBlock({
            return UITracingLayerView()
        })
        
        self.addSubnode(self.listNode)
        
        switch self.mode {
            case .tab:
                self.backgroundColor = presentationData.theme.chatList.backgroundColor
                self.listNode.backgroundColor = presentationData.theme.chatList.backgroundColor
            case .navigation:
                self.backgroundColor = presentationData.theme.list.blocksBackgroundColor
                self.listNode.backgroundColor = presentationData.theme.list.blocksBackgroundColor
        }
        
        let nodeInteraction = CallListNodeInteraction(setMessageIdWithRevealedOptions: { [weak self] messageId, fromMessageId in
            if let strongSelf = self {
                strongSelf.updateState { state in
                    if (messageId == nil && fromMessageId == state.messageIdWithRevealedOptions) || (messageId != nil && fromMessageId == nil) {
                        return state.withUpdatedMessageIdWithRevealedOptions(messageId)
                    } else {
                        return state
                    }
                }
            }
        }, call: { [weak self] peerId in
            self?.call(peerId)
        }, openInfo: { [weak self] peerId in
            self?.openInfo(peerId)
        }, delete: { [weak self] messageIds in
            if let strongSelf = self {
                let _ = deleteMessagesInteractively(postbox: strongSelf.account.postbox, messageIds: messageIds, type: .forLocalPeer).start()
            }
        }, updateShowCallsTab: { [weak self] value in
            if let strongSelf = self {
                let _ = updateCallListSettingsInteractively(postbox: strongSelf.account.postbox, {
                    $0.withUpdatedShowTab(value)
                }).start()
            }
        })
        
        let viewProcessingQueue = self.viewProcessingQueue
        
        let callListViewUpdate = self.callListLocationAndType.get()
            |> distinctUntilChanged
            |> mapToSignal { locationAndType in
                return callListViewForLocationAndType(locationAndType: locationAndType, account: account)
            }
        
        let previousView = Atomic<CallListNodeView?>(value: nil)
        
        let showSettings: Bool
        switch mode {
            case .tab:
                showSettings = false
            case .navigation:
                showSettings = true
        }
        
        let showCallsTab = account.postbox.preferencesView(keys: [ApplicationSpecificPreferencesKeys.callListSettings])
            |> map { view -> Bool in
                var value = true
                if let settings = view.values[ApplicationSpecificPreferencesKeys.callListSettings] as? CallListSettings {
                    value = settings.showTab
                }
                return value
            }
        
        let callListNodeViewTransition = combineLatest(callListViewUpdate, self.statePromise.get(), showCallsTab) |> mapToQueue { (update, state, showCallsTab) -> Signal<CallListNodeListViewTransition, NoError> in
            let processedView = CallListNodeView(originalView: update.view, filteredEntries: callListNodeEntriesForView(update.view, state: state, showSettings: showSettings, showCallsTab: showCallsTab))
            let previous = previousView.swap(processedView)
            
            let reason: CallListNodeViewTransitionReason
            var prepareOnMainQueue = false
            
            var previousWasEmptyOrSingleHole = false
            if let previous = previous {
                if previous.filteredEntries.count == 1 {
                    if case .holeEntry = previous.filteredEntries[0] {
                        previousWasEmptyOrSingleHole = true
                    }
                }
            } else {
                previousWasEmptyOrSingleHole = true
            }
            
            if previousWasEmptyOrSingleHole {
                reason = .initial
                if previous == nil {
                    prepareOnMainQueue = true
                }
            } else {
                if previous?.originalView === update.view {
                    reason = .interactiveChanges
                } else {
                    switch update.type {
                        case .Initial:
                            reason = .initial
                            prepareOnMainQueue = true
                        case .Generic:
                            reason = .interactiveChanges
                        case .UpdateVisible:
                            reason = .reload
                        case .Reload:
                            reason = .reload
                        case .ReloadAnimated:
                            reason = .reloadAnimated
                    }
                }
            }
            
            return preparedCallListNodeViewTransition(from: previous, to: processedView, reason: reason, account: account, scrollPosition: update.scrollPosition)
                |> map({ mappedCallListNodeViewListTransition(account: account, showSettings: showSettings, nodeInteraction: nodeInteraction, transition: $0) })
                |> runOn(prepareOnMainQueue ? Queue.mainQueue() : viewProcessingQueue)
        }
        
        let appliedTransition = callListNodeViewTransition |> deliverOnMainQueue |> mapToQueue { [weak self] transition -> Signal<Void, NoError> in
            if let strongSelf = self {
                return strongSelf.enqueueTransition(transition)
            }
            return .complete()
        }
        
        self.listNode.displayedItemRangeChanged = { [weak self] range, transactionOpaqueState in
            if let strongSelf = self, let range = range.loadedRange, let view = (transactionOpaqueState as? CallListOpaqueTransactionState)?.callListView.originalView {
                var location: CallListNodeLocation?
                if range.firstIndex < 5 && view.later != nil {
                    location = .navigation(index: view.entries[view.entries.count - 1].highestIndex)
                } else if range.firstIndex >= 5 && range.lastIndex >= view.entries.count - 5 && view.earlier != nil {
                    location = .navigation(index: view.entries[0].lowestIndex)
                }
                
                if let location = location, location != strongSelf.currentLocationAndType.location {
                    strongSelf.currentLocationAndType = CallListNodeLocationAndType(location: location, type: strongSelf.currentLocationAndType.type)
                    strongSelf.callListLocationAndType.set(strongSelf.currentLocationAndType)
                }
            }
        }
        
        self.callListDisposable.set(appliedTransition.start())
        
        self.callListLocationAndType.set(self.currentLocationAndType)
    }
    
    deinit {
        self.callListDisposable.dispose()
    }
    
    func updateThemeAndStrings(theme: PresentationTheme, strings: PresentationStrings) {
        if theme !== self.currentState.theme || strings !== self.currentState.strings {
            switch self.mode {
                case .tab:
                    self.backgroundColor = theme.chatList.backgroundColor
                    self.listNode.backgroundColor = theme.chatList.backgroundColor
                case .navigation:
                    self.backgroundColor = theme.list.blocksBackgroundColor
                    self.listNode.backgroundColor = theme.list.blocksBackgroundColor
            }
            
            self.updateState {
                return $0.withUpdatedPresentationData(theme: theme, strings: strings)
            }
        }
    }
    
    func updateState(_ f: (CallListNodeState) -> CallListNodeState) {
        let state = f(self.currentState)
        if state != self.currentState {
            self.currentState = state
            self.statePromise.set(state)
        }
    }
    
    func updateType(_ type: CallListViewType) {
        if type != self.currentLocationAndType.type {
            if let view = self.callListView?.originalView {
                var index: MessageIndex
                if !view.entries.isEmpty {
                    index = view.entries[view.entries.count - 1].highestIndex
                } else {
                    index = MessageIndex.absoluteUpperBound()
                }
                self.currentLocationAndType = CallListNodeLocationAndType(location: .changeType(index: index), type: type)
                self.callListLocationAndType.set(self.currentLocationAndType)
            }
        }
    }
    
    private func enqueueTransition(_ transition: CallListNodeListViewTransition) -> Signal<Void, NoError> {
        return Signal { [weak self] subscriber in
            if let strongSelf = self {
                if let _ = strongSelf.enqueuedTransition {
                    preconditionFailure()
                }
                
                strongSelf.enqueuedTransition = (transition, {
                    subscriber.putCompletion()
                })
                
                if strongSelf.isNodeLoaded {
                    strongSelf.dequeueTransition()
                } else {
                    if !strongSelf.didSetReady {
                        strongSelf.didSetReady = true
                        strongSelf._ready.set(true)
                    }
                }
            } else {
                subscriber.putCompletion()
            }
            
            return EmptyDisposable
        } |> runOn(Queue.mainQueue())
    }
    
    private func dequeueTransition() {
        if let (transition, completion) = self.enqueuedTransition {
            self.enqueuedTransition = nil
            
            let completion: (ListViewDisplayedItemRange) -> Void = { [weak self] visibleRange in
                if let strongSelf = self {
                    strongSelf.callListView = transition.callListView
                    
                    strongSelf.emptyStateUpdated(transition.callListView.filteredEntries.isEmpty)
                    
                    if !strongSelf.didSetReady {
                        strongSelf.didSetReady = true
                        strongSelf._ready.set(true)
                    }
                    
                    completion()
                }
            }
            
            self.listNode.transaction(deleteIndices: transition.deleteItems, insertIndicesAndItems: transition.insertItems, updateIndicesAndItems: transition.updateItems, options: transition.options, scrollToItem: transition.scrollToItem, stationaryItemRange: transition.stationaryItemRange, updateOpaqueState: CallListOpaqueTransactionState(callListView: transition.callListView), completion: completion)
        }
    }
    
    func scrollToLatest() {
        if let view = self.callListView?.originalView, view.later == nil {
            self.listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous], scrollToItem: ListViewScrollToItem(index: 0, position: .top(0.0), animated: true, curve: .Default, directionHint: .Up), updateSizeAndInsets: nil, stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
        } else {
            let location: CallListNodeLocation = .scroll(index: MessageIndex.absoluteUpperBound(), sourceIndex: MessageIndex.absoluteLowerBound(), scrollPosition: .top(0.0), animated: true)
            self.currentLocationAndType = CallListNodeLocationAndType(location: location, type: self.currentLocationAndType.type)
            self.callListLocationAndType.set(self.currentLocationAndType)
        }
    }
    
    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        self.containerLayout = (layout, navigationBarHeight)
        
        var insets = layout.insets(options: [.input])
        insets.top += max(navigationBarHeight, layout.insets(options: [.statusBar]).top)
        insets.left += layout.safeInsets.left
        insets.right += layout.safeInsets.right
        
        self.listNode.bounds = CGRect(x: 0.0, y: 0.0, width: layout.size.width, height: layout.size.height)
        self.listNode.position = CGPoint(x: layout.size.width / 2.0, y: layout.size.height / 2.0)
        
        var duration: Double = 0.0
        var curve: UInt = 0
        switch transition {
            case .immediate:
                break
            case let .animated(animationDuration, animationCurve):
                duration = animationDuration
                switch animationCurve {
                    case .easeInOut:
                        break
                    case .spring:
                        curve = 7
                }
        }
        
        let listViewCurve: ListViewAnimationCurve
        if curve == 7 {
            listViewCurve = .Spring(duration: duration)
        } else {
            listViewCurve = .Default
        }
        
        let updateSizeAndInsets = ListViewUpdateSizeAndInsets(size: layout.size, insets: insets, duration: duration, curve: listViewCurve)
        
        self.listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous, .LowLatency], scrollToItem: nil, updateSizeAndInsets: updateSizeAndInsets, stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
        
        if !self.dequeuedInitialTransitionOnLayout {
            self.dequeuedInitialTransitionOnLayout = true
            self.dequeueTransition()
        }
    }
}
