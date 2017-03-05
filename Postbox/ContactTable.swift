import Foundation

final class ContactTable: Table {
    static func tableSpec(_ id: Int32) -> ValueBoxTable {
        return ValueBoxTable(id: id, keyType: .binary)
    }
    
    private let peerNameIndexTable: PeerNameIndexTable
    
    private var peerIdsBeforeModification: Set<PeerId>?
    private var peerIds: Set<PeerId>?
    
    init(valueBox: ValueBox, table: ValueBoxTable, peerNameIndexTable: PeerNameIndexTable) {
        self.peerNameIndexTable = peerNameIndexTable
        
        super.init(valueBox: valueBox, table: table)
    }
    
    private func key(_ id: PeerId, sharedKey: ValueBoxKey = ValueBoxKey(length: 8)) -> ValueBoxKey {
        sharedKey.setInt64(0, value: id.toInt64())
        return sharedKey
    }
    
    private func lowerBound() -> ValueBoxKey {
        return self.key(PeerId(namespace: 0, id: 0))
    }
    
    private func upperBound() -> ValueBoxKey {
        return self.key(PeerId(namespace: Int32.max, id: Int32.max))
    }
    
    func isContact(peerId: PeerId) -> Bool {
        return self.get().contains(peerId)
    }
    
    func get() -> Set<PeerId> {
        if let peerIds = self.peerIds {
            return peerIds
        } else {
            var peerIds = Set<PeerId>()
            self.valueBox.range(self.table, start: self.lowerBound(), end: self.upperBound(), keys: { key in
                peerIds.insert(PeerId(key.getInt64(0)))
                return true
            }, limit: 0)
            self.peerIds = peerIds
            return peerIds
        }
    }
    
    func replace(_ ids: Set<PeerId>) {
        if self.peerIdsBeforeModification == nil {
           self.peerIdsBeforeModification = self.get()
        }
        
        self.peerIds = ids
    }
    
    override func clearMemoryCache() {
        assert(self.peerIdsBeforeModification == nil)
        self.peerIds = nil
    }
    
    override func beforeCommit() {
        if let peerIdsBeforeModification = self.peerIdsBeforeModification {
            if let peerIds = self.peerIds {
                let removedPeerIds = peerIdsBeforeModification.subtracting(peerIds)
                let addedPeerIds = peerIds.subtracting(peerIdsBeforeModification)
                
                let sharedKey = self.key(PeerId(namespace: 0, id: 0))
                
                for peerId in removedPeerIds {
                    self.valueBox.remove(self.table, key: self.key(peerId, sharedKey: sharedKey))
                    self.peerNameIndexTable.setPeerCategoryState(peerId: peerId, category: [.contacts], includes: false)
                }
                
                for peerId in addedPeerIds {
                    self.valueBox.set(self.table, key: self.key(peerId, sharedKey: sharedKey), value: MemoryBuffer())
                    self.peerNameIndexTable.setPeerCategoryState(peerId: peerId, category: [.contacts], includes: true)
                }
            } else {
                assertionFailure()
            }
            
            self.peerIdsBeforeModification = nil
        }
    }
}
