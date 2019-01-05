//
//  SyncSource.swift
//  IceCream
//
//  Created by David Collado on 1/5/18.
//

import CloudKit
import Foundation
import RealmSwift

/// SyncObject is for each model you want to sync.
/// Logically,
/// 1. it takes care of the operations of CKRecordZone.
/// 2. it detects the changeSets of Realm Database and directly talks to it.
/// 3. it hands over to SyncEngine so that it can talk to CloudKit.

public final class SyncObject<T> where T: Object & CKRecordConvertible & CKRecordRecoverable {
    /// Notifications are delivered as long as a reference is held to the returned notification token. We should keep a strong reference to this token on the class registering for updates, as notifications are automatically unregistered when the notification token is deallocated.
    /// For more, reference is here: https://realm.io/docs/swift/latest/#notifications
    private var notificationToken: NotificationToken?
    
    private var backgroundWorker = BackgroundWorker()
    
    public var pipeToEngine: ((_ recordsToStore: [CKRecord], _ recordIDsToDelete: [CKRecord.ID]) -> ())?
    
    public init() {}
}

// MARK: - Zone information

extension SyncObject: Syncable {
    public var recordType: String {
        return T.recordType
    }

    public var customZoneID: CKRecordZone.ID {
        return T.customZoneID
    }
    
    public var zoneChangesToken: CKServerChangeToken? {
        get {
            /// For the very first time when launching, the token will be nil and the server will be giving everything on the Cloud to client
            /// In other situation just get the unarchive the data object
            guard let tokenData = UserDefaults.standard.object(forKey: T.className() + IceCreamKey.zoneChangesTokenKey.value) as? Data else { return nil }
            return NSKeyedUnarchiver.unarchiveObject(with: tokenData) as? CKServerChangeToken
        }
        set {
            guard let n = newValue else {
                UserDefaults.standard.removeObject(forKey: T.className() + IceCreamKey.zoneChangesTokenKey.value)
                return
            }
            let data = NSKeyedArchiver.archivedData(withRootObject: n)
            UserDefaults.standard.set(data, forKey: T.className() + IceCreamKey.zoneChangesTokenKey.value)
        }
    }
    
    public var isCustomZoneCreated: Bool {
        get {
            guard let flag = UserDefaults.standard.object(forKey: T.className() + IceCreamKey.hasCustomZoneCreatedKey.value) as? Bool else { return false }
            return flag
        }
        set {
            UserDefaults.standard.set(newValue, forKey: T.className() + IceCreamKey.hasCustomZoneCreatedKey.value)
        }
    }
    
    public func add(record: CKRecord) {
        backgroundWorker.perform { [weak self] in
            guard let self = self else { return }
            let realm = try! Realm()
            guard let object = T().parseFromRecord(record: record, realm: realm) else {
                print("There is something wrong with the converson from cloud record to local object")
                return
            }
            /// If your model class includes a primary key, you can have Realm intelligently update or add objects based off of their primary key values using Realm().add(_:update:).
            /// https://realm.io/docs/swift/latest/#objects-with-primary-keys
            realm.beginWrite()
            realm.add(object, update: true)
            try! realm.commitWrite(withoutNotifying: [self.notificationToken!])
        }
    }
    
    public func delete(recordID: CKRecord.ID) {
        backgroundWorker.perform { [weak self] in
            guard let self = self else { return }
            let realm = try! Realm()
            guard let object = realm.object(ofType: T.self, forPrimaryKey: recordID.recordName) else {
                // Not found in local realm database
                return
            }
            CreamAsset.deleteCreamAssetFile(with: recordID.recordName)
            realm.beginWrite()
            realm.delete(object)
            try! realm.commitWrite(withoutNotifying: [self.notificationToken!])
        }
    }
    
    /// When you commit a write transaction to a Realm, all other instances of that Realm will be notified, and be updated automatically.
    /// For more: https://realm.io/docs/swift/latest/#writes
    public func registerLocalDatabase() {
        backgroundWorker.perform { [weak self] in
            guard let self = self else { return }
            let objects = Cream<T>().realm.objects(T.self)
            
            self.notificationToken = objects.observe({ [weak self] changes in
                guard let self = self else { return }
                switch changes {
                case .initial:
                    break
                case .update(let collection, _, let insertions, let modifications):
                    let recordsToStore = (insertions + modifications).filter { $0 < collection.count }.map { collection[$0] }.filter { !$0.isDeleted }.map { $0.record }
                    let recordIDsToDelete = modifications.filter { $0 < collection.count }.map { collection[$0] }.filter { $0.isDeleted }.map { $0.recordID }
                    DispatchQueue.main.async {
                        print("RECORDS TO STORE", recordsToStore)
                        print("RECORD IDS TO DELETE", recordIDsToDelete)
                    }
                    
                    guard recordsToStore.count > 0 || recordIDsToDelete.count > 0 else { return }
                    self.pipeToEngine?(recordsToStore, recordIDsToDelete)
                case .error:
                    break
                }
            })
        }
    }
    
    public func cleanUp() {
        backgroundWorker.perform { [weak self] in
            guard let self = self else { return }
            let cream = Cream<T>()
            do {
                try cream.deletePreviousSoftDeleteObjects(notNotifying: self.notificationToken)
            } catch {
                // Error handles here
            }
        }
    }
    
    public func pushLocalObjectsToCloudKit() {
        let recordsToStore: [CKRecord] = Cream<T>().realm.objects(T.self).filter { !$0.isDeleted }.map { $0.record }
        pipeToEngine?(recordsToStore, [])
    }
}
