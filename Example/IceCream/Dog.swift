//
//  Dog.swift
//  IceCream_Example
//
//  Created by 蔡越 on 23/10/2017.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import Foundation
import RealmSwift
import IceCream
import CloudKit

class Dog: Object {
    @objc dynamic var id = NSUUID().uuidString
    @objc dynamic var name = ""
    @objc dynamic var age = 0
    
    override class func primaryKey() -> String? {
        return "id"
    }
}

extension Dog: CKRecordConvertible {
    /// recordName : this is the unique identifier for the record, used to locate records on the database. We can create our own ID or leave it to CloudKit to generate a random UUID.
    /// For more: https://medium.com/@guilhermerambo/synchronizing-data-with-cloudkit-94c6246a3fda
    var recordID: CKRecordID {
        return CKRecordID(recordName: id)
    }
    
    var record: CKRecord {
        let r = CKRecord(recordType: Dog.recordType, recordID: recordID)
        r[.id] = id as CKRecordValue
        r[.age] = age as CKRecordValue
        r[.name] = name as CKRecordValue
        return r
    }
    
    static var recordType: String {
        return "Dog"
    }
}

enum DogKey: String {
    case id
    case name
    case age
}

extension CKRecord {
    subscript(_ key: DogKey) -> CKRecordValue {
        get {
            return self[key.rawValue]!
        }
        set {
            self[key.rawValue] = newValue
        }
    }
}
