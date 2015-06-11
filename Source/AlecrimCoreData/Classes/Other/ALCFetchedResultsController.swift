//
//  ALCFetchedResultsController.swift
//  AlecrimCoreData
//
//  Created by Vanderlei Martinelli on 2015-06-08.
//  Copyright (c) 2015 Alecrim. All rights reserved.
//

#if os(OSX)

import Foundation
import CoreData

// MARK: -

public typealias NSFetchedResultsChangeType = ALCFetchedResultsChangeType
public typealias NSFetchedResultsSectionInfo = ALCFetchedResultsSectionInfo
public typealias NSFetchedResultsControllerDelegate = ALCFetchedResultsControllerDelegate
public typealias NSFetchedResultsController = ALCFetchedResultsController


// MARK: -

@objc public enum ALCFetchedResultsChangeType : UInt {
    case Insert
    case Delete
    case Move
    case Update
}

// MARK: -

@objc public protocol ALCFetchedResultsSectionInfo {
    var name: String? { get }
    var indexTitle: String { get }
    var numberOfObjects: Int { get }
    var objects: [AnyObject] { get }
}

// MARK: -

@objc public protocol ALCFetchedResultsControllerDelegate: class {
    optional func controller(controller: ALCFetchedResultsController, didChangeObject anObject: AnyObject, atIndexPath indexPath: NSIndexPath?, forChangeType type: ALCFetchedResultsChangeType, newIndexPath: NSIndexPath?)
    optional func controller(controller: ALCFetchedResultsController, didChangeSection sectionInfo: ALCFetchedResultsSectionInfo, atIndex sectionIndex: Int, forChangeType type: ALCFetchedResultsChangeType)
    optional func controllerWillChangeContent(controller: ALCFetchedResultsController)
    optional func controllerDidChangeContent(controller: ALCFetchedResultsController)
    optional func controller(controller: ALCFetchedResultsController, sectionIndexTitleForSectionName sectionName: String?) -> String?
}

// MARK: -

public class ALCFetchedResultsController: NSObject {
    
    public let observedManagedObjectContext: NSManagedObjectContext

    
    // MARK: -
    
    public let fetchRequest: NSFetchRequest
    public let managedObjectContext: NSManagedObjectContext
    public let sectionNameKeyPath: String?
    public let cacheName: String? // never used in this implementation
    
    // MARK: -
    
    public weak var delegate: ALCFetchedResultsControllerDelegate?

    // MARK: -

    public class func deleteCacheWithName(name: String?) {
        // do nothing in this implementation
    }

    // MARK: -

    public private(set) var sections: [AnyObject]?
    public private(set) var fetchedObjects: [AnyObject]?

    private var _sectionIndexTitles: [AnyObject]? = nil
    public var sectionIndexTitles: [AnyObject] {
        if self._sectionIndexTitles == nil {
            if let sections = self.sections as? [ALCSectionInfo] {
                self._sectionIndexTitles = [AnyObject]()
                for section in sections {
                    let sectionIndexTitle = (self.delegate?.controller?(self, sectionIndexTitleForSectionName: section.name) ?? self.sectionIndexTitleForSectionName(section.name)) ?? ""
                    self._sectionIndexTitles!.append(sectionIndexTitle)
                }
            }
        }
        
        return self._sectionIndexTitles ?? [AnyObject]()
    }
    
    // MARK: -
    
    public init(fetchRequest: NSFetchRequest, managedObjectContext context: NSManagedObjectContext, sectionNameKeyPath: String?, cacheName name: String?) {
        //
        self.fetchRequest = fetchRequest
        self.managedObjectContext = context
        self.sectionNameKeyPath = sectionNameKeyPath
        self.cacheName = name
        
        //
        var observedManagedObjectContext = managedObjectContext
        while observedManagedObjectContext.parentContext != nil {
            observedManagedObjectContext = observedManagedObjectContext.parentContext!
        }
        
        self.observedManagedObjectContext = observedManagedObjectContext
        
        //
        super.init()
        
        //
        NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("handleContextChangesWithNotification:"), name: NSManagedObjectContextDidSaveNotification, object: self.observedManagedObjectContext)
    }
    
    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self, name: NSManagedObjectContextDidSaveNotification, object: self.observedManagedObjectContext)
    }
    
    // MARK: -

    public func performFetch(error: NSErrorPointer) -> Bool {
        return self.calculateSections(error: error).success
    }
    
    public func objectAtIndexPath(indexPath: NSIndexPath) -> AnyObject {
        if let section = self.sections?[indexPath.section] as? ALCSectionInfo {
            if let fetchedObjects = self.fetchedObjects {
                return fetchedObjects[section.range.location + indexPath.item]
            }
        }
        
        fatalError("Object not found and we cannot return nil")
    }

    public func indexPathForObject(object: AnyObject) -> NSIndexPath? {
        var indexPath: NSIndexPath? = nil
        
        if let sections = self.sections as? [ALCSectionInfo], fetchedObjects = self.fetchedObjects {
            let index = (fetchedObjects as NSArray).indexOfObject(object)
            if index != NSNotFound {
                var sectionIndex = 0
                for section in sections {
                    if NSLocationInRange(index, section.range) {
                        let itemIndex = index - section.range.location
                        indexPath = NSIndexPath(forItem: itemIndex, inSection: sectionIndex)
                        break
                    }
                    
                    sectionIndex++
                }
            }
        }
        
        return indexPath
    }
    
    // MARK: -
    
    public func sectionIndexTitleForSectionName(sectionName: String?) -> String? {
        if let sectionName = sectionName {
            let string = sectionName as NSString
            if string.length > 0 {
                return string.substringToIndex(1).capitalizedString
            }
            else {
                return ""
            }
        }
        
        return nil
    }
    
    public func sectionForSectionIndexTitle(title: String, atIndex sectionIndex: Int) -> Int {
        return sectionIndex
    }
    
}

// MARK: -

extension ALCFetchedResultsController {
    
    @objc private func handleContextChangesWithNotification(notification: NSNotification) {
        //
        if self.fetchedObjects == nil {
            // we need a performFetch: call first
            return
        }
        
        //
        if let savedContext = notification.object as? NSManagedObjectContext {
            let contextInsertedObjects = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> ?? Set<NSManagedObject>()
            let contextUpdatedObjects = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> ?? Set<NSManagedObject>()
            let contextDeletedObjects = notification.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject> ?? Set<NSManagedObject>()
            
            var insertedObjects = filter(contextInsertedObjects, { $0.entity.name == self.fetchRequest.entityName }).map { $0.inManagedObjectContext(self.managedObjectContext)! }
            let updatedObjects = filter(contextUpdatedObjects, { $0.entity.name == self.fetchRequest.entityName }).map { $0.inManagedObjectContext(self.managedObjectContext)! }
            var deletedObjects = filter(contextDeletedObjects, { $0.entity.name == self.fetchRequest.entityName }).map { $0.inManagedObjectContext(self.managedObjectContext)! }
            
            if let predicate = self.fetchRequest.predicate {
                insertedObjects = (insertedObjects as NSArray).filteredArrayUsingPredicate(predicate) as! [NSManagedObject]
                deletedObjects = (deletedObjects as NSArray).filteredArrayUsingPredicate(predicate) as! [NSManagedObject]
            }
            
            if insertedObjects.count > 0 || updatedObjects.count > 0 || deletedObjects.count > 0 {
                let (success, oldSections, oldFetchedObjects, newSections, newFetchedObjects) = self.calculateSections(error: nil)
                if success && self.delegate != nil && oldSections != nil && oldFetchedObjects != nil && newSections != nil && newFetchedObjects != nil {
                    self.handleCallbacksWithDelegate(self.delegate!, oldSections: oldSections as! [ALCSectionInfo], oldFetchedObjects: oldFetchedObjects as! [NSManagedObject], newSections: self.sections as! [ALCSectionInfo], newFetchedObjects: self.fetchedObjects as! [NSManagedObject], insertedObjects: insertedObjects, updatedObjects: updatedObjects, deletedObjects: deletedObjects)
                }
            }
        }
    }
    
}

// MARK: -

extension ALCFetchedResultsController {
    
    private func calculateSections(error errorPointer: NSErrorPointer) -> (success: Bool, oldSections: [AnyObject]?, oldFetchedObjects: [AnyObject]?, newSections: [AnyObject]?, newFetchedObjects: [AnyObject]?) {
        var oldSections = self.sections
        var oldFetchedObjects = self.fetchedObjects
        
        //
        self.sections = nil
        self.fetchedObjects = nil
        self._sectionIndexTitles = nil

        //
        if let sectionNameKeyPath = self.sectionNameKeyPath {
            //
            var calculatedSections = [ALCSectionInfo]()
            
            //
            let countFetchRequest = self.fetchRequest.copy() as! NSFetchRequest
            countFetchRequest.fetchOffset = 0
            countFetchRequest.fetchLimit = 0
            countFetchRequest.fetchBatchSize = 0
            
            countFetchRequest.propertiesToFetch = nil
            countFetchRequest.resultType = .DictionaryResultType
            countFetchRequest.relationshipKeyPathsForPrefetching = nil
            
            let countDescription = NSExpressionDescription()
            countDescription.name = "count"
            countDescription.expression = NSExpression(forFunction: "count:", arguments: [NSExpression.expressionForEvaluatedObject()])
            countDescription.expressionResultType = .Integer32AttributeType
            
            countFetchRequest.propertiesToFetch = [self.sectionNameKeyPath!, countDescription]
            countFetchRequest.propertiesToGroupBy = [self.sectionNameKeyPath!]
            
            var countFetchRequestError: NSError? = nil
            var results: [AnyObject]? = nil
            //self.managedObjectContext.performBlockAndWait {
                results = self.managedObjectContext.executeFetchRequest(countFetchRequest, error: &countFetchRequestError)
            //}
            
            if countFetchRequestError != nil {
                errorPointer.memory = countFetchRequestError
                return (false, oldSections, oldFetchedObjects, self.sections, self.fetchedObjects)
            }
            
            //
            var fetchedObjectsCount = 0
            var offset = self.fetchRequest.fetchOffset
            let limit = self.fetchRequest.fetchLimit
            
            if let dicts = results as? [NSDictionary] {
                for dict in dicts {
                    if let _count = (dict["count"] as? NSNumber)?.intValue {
                        var count = Int(_count)
                        
                        if offset >= count {
                            offset -= count
                            continue
                        }
                        
                        let _value: AnyObject? = dict[sectionNameKeyPath]
                        let sectionFetchRequest = self.fetchRequest.copy() as! NSFetchRequest
                        
                        let sectionPredicate: NSPredicate
                        if let value: AnyObject = _value {
                            sectionPredicate = NSPredicate(format: "%K == %@", argumentArray: [sectionNameKeyPath, value])
                        }
                        else {
                            sectionPredicate = NSPredicate(format: "%K == nil", argumentArray: [sectionNameKeyPath])
                        }
                        
                        if let predicate = sectionFetchRequest.predicate {
                            sectionFetchRequest.predicate = NSCompoundPredicate(type: .AndPredicateType, subpredicates: [sectionPredicate, predicate])
                        }
                        else {
                            sectionFetchRequest.predicate = sectionPredicate
                        }
                        
                        //
                        count -= offset
                        if limit > 0 {
                            count = min(count, limit - fetchedObjectsCount)
                        }

                        //
                        let sectionName: String
                        if let string = _value as? String {
                            sectionName = string
                        }
                        else if let object = _value as? NSObject {
                            sectionName = object.description
                        }
                        else {
                            sectionName = "\(_value)"
                        }

                        let sectionIndexTitle = (self.delegate?.controller?(self, sectionIndexTitleForSectionName: sectionName) ?? self.sectionIndexTitleForSectionName(sectionName)) ?? ""
                        
                        let section = ALCSectionInfo(fetchedResultsController: self, range: NSMakeRange(fetchedObjectsCount, count), name: sectionName, indexTitle: sectionIndexTitle)
                        
                        calculatedSections.append(section)
                        
                        //
                        fetchedObjectsCount += count
                        offset -= min(count, offset)
                        
                        if limit > 0 && fetchedObjectsCount == limit {
                            break
                        }
                    }
                }
            }
            
            //
            //self.managedObjectContext.performBlockAndWait {
            var error: NSError? = nil
            self.fetchedObjects = self.managedObjectContext.executeFetchRequest(self.fetchRequest, error: &error)
            //}

            if error != nil {
                errorPointer.memory = error
                return (false, oldSections, oldFetchedObjects, self.sections, self.fetchedObjects)
            }

            //
            self.sections = calculatedSections
        }
        else {
            //self.managedObjectContext.performBlockAndWait {
            var error: NSError? = nil
            self.fetchedObjects = self.managedObjectContext.executeFetchRequest(self.fetchRequest, error: &error)
            //}
            
            if error != nil {
                errorPointer.memory = error
                return (false, oldSections, oldFetchedObjects, self.sections, self.fetchedObjects)
            }

            //
            let section = ALCSectionInfo(fetchedResultsController: self, range: NSMakeRange(0, self.fetchedObjects?.count ?? 0), name: nil, indexTitle: "")
            self.sections = [section]
        }
        
        
        //
        return (true, oldSections, oldFetchedObjects, self.sections, self.fetchedObjects)
    }
    
    private func handleCallbacksWithDelegate(delegate: ALCFetchedResultsControllerDelegate, oldSections: [ALCSectionInfo], oldFetchedObjects: [NSManagedObject], newSections: [ALCSectionInfo], newFetchedObjects: [NSManagedObject], var insertedObjects: [NSManagedObject], var updatedObjects: [NSManagedObject], var deletedObjects: [NSManagedObject]) {
        //
        var controllerWillChangeContentCalled = false

        //
        func callControllerWillChangeContentIfNeeded() {
            if !controllerWillChangeContentCalled {
                controllerWillChangeContentCalled = true
                delegate.controllerWillChangeContent?(self)
            }
        }
        
        //
        var movedObjects = [NSManagedObject]()

        //
        for oldSectionIndex in oldSections.startIndex..<oldSections.endIndex {
            var foundNewSectionIndex: Int? = nil
            for newSectionIndex in newSections.startIndex..<newSections.endIndex {
                if newSections[newSectionIndex].name == oldSections[oldSectionIndex].name {
                    foundNewSectionIndex = newSectionIndex
                    break
                }
            }
            
            if foundNewSectionIndex == nil {
                callControllerWillChangeContentIfNeeded()
                delegate.controller?(self, didChangeSection: oldSections[oldSectionIndex], atIndex: oldSectionIndex, forChangeType: .Delete)
            }
        }
        
        //
        for newSectionIndex in newSections.startIndex..<newSections.endIndex {
            var foundOldSectionIndex: Int? = nil
            for oldSectionIndex in oldSections.startIndex..<oldSections.endIndex {
                if oldSections[oldSectionIndex].name == newSections[newSectionIndex].name {
                    foundOldSectionIndex = oldSectionIndex
                    break
                }
            }
            
            if foundOldSectionIndex == nil {
                callControllerWillChangeContentIfNeeded()
                delegate.controller?(self, didChangeSection: newSections[newSectionIndex], atIndex: newSectionIndex, forChangeType: .Insert)
            }
        }
        
        //
        let updatedObjectsCopy = updatedObjects
        for updatedObject in updatedObjectsCopy {
            var oldIndexPath: NSIndexPath? = nil
            var newIndexPath: NSIndexPath? = nil
            
            //
            let oldIndex = (oldFetchedObjects as NSArray).indexOfObject(updatedObject)
            if oldIndex != NSNotFound {
                for oldSectionIndex in oldSections.startIndex..<oldSections.endIndex {
                    let oldSection = oldSections[oldSectionIndex]
                    if NSLocationInRange(oldIndex, oldSection.range) {
                        let oldItemIndex = oldIndex - oldSection.range.location
                        oldIndexPath = NSIndexPath(forItem: oldItemIndex, inSection: oldSectionIndex)
                        break
                    }
                }
            }
            
            //
            let newIndex = (newFetchedObjects as NSArray).indexOfObject(updatedObject)
            if newIndex != NSNotFound {
                for newSectionIndex in newSections.startIndex..<newSections.endIndex {
                    let newSection = newSections[newSectionIndex]
                    if NSLocationInRange(newIndex, newSection.range) {
                        let newItemIndex = newIndex - newSection.range.location
                        newIndexPath = NSIndexPath(forItem: newItemIndex, inSection: newSectionIndex)
                        break
                    }
                }
            }
            
            //
            if newIndexPath == nil {
                if let index = find(updatedObjects, updatedObject) {
                    updatedObjects.removeAtIndex(index)
                }
                
                if let predicate = self.fetchRequest.predicate where predicate.evaluateWithObject(updatedObject) {
                    deletedObjects.append(updatedObject)
                }
            }
            else if oldIndexPath == nil {
                if let index = find(updatedObjects, updatedObject) {
                    updatedObjects.removeAtIndex(index)
                }
                
                if let predicate = self.fetchRequest.predicate where predicate.evaluateWithObject(updatedObject) {
                    insertedObjects.append(updatedObject)
                }
            }
            else {
                if let predicate = self.fetchRequest.predicate where predicate.evaluateWithObject(updatedObject) {
                    var inSortDescriptors = false
                    if let changedValues = updatedObject.changedValues() as? [String: AnyObject], let sortDescriptors = self.fetchRequest.sortDescriptors as? [NSSortDescriptor] {
                        for changedValueKey in changedValues.keys {
                            for sortDescriptor in sortDescriptors {
                                if let sortDescriptorKey = sortDescriptor.key() {
                                    if sortDescriptorKey == changedValueKey {
                                        inSortDescriptors = true
                                        break
                                    }
                                }
                            }
                            if inSortDescriptors {
                                break
                            }
                        }
                    }
                    
                    if inSortDescriptors {
                        if let index = find(updatedObjects, updatedObject) {
                            updatedObjects.removeAtIndex(index)
                        }
                        
                        movedObjects.append(updatedObject)
                    }
                }
                else {
                    if let index = find(updatedObjects, updatedObject) {
                        updatedObjects.removeAtIndex(index)
                    }
                }
            }
        }
        
        //
        for deletedObject in deletedObjects {
            let oldIndex = (oldFetchedObjects as NSArray).indexOfObject(deletedObject)
            for oldSectionIndex in oldSections.startIndex..<oldSections.endIndex {
                let oldSection = oldSections[oldSectionIndex]
                if NSLocationInRange(oldIndex, oldSection.range) {
                    let oldItemIndex = oldIndex - oldSection.range.location
                    let oldIndexPath = NSIndexPath(forItem: oldItemIndex, inSection: oldSectionIndex)

                    callControllerWillChangeContentIfNeeded()
                    delegate.controller?(self, didChangeObject: deletedObject, atIndexPath: oldIndexPath, forChangeType: .Delete, newIndexPath: nil)
                    break
                }
            }
        }
        
        //
        for insertedObject in insertedObjects {
            let newIndex = (newFetchedObjects as NSArray).indexOfObject(insertedObject)
            for newSectionIndex in newSections.startIndex..<newSections.endIndex {
                let newSection = newSections[newSectionIndex]
                if NSLocationInRange(newIndex, newSection.range) {
                    let newItemIndex = newIndex - newSection.range.location
                    let newIndexPath = NSIndexPath(forItem: newItemIndex, inSection: newSectionIndex)

                    callControllerWillChangeContentIfNeeded()
                    delegate.controller?(self, didChangeObject: insertedObject, atIndexPath: nil, forChangeType: .Insert, newIndexPath: newIndexPath)
                    break
                }
            }
        }
        
        // On add and remove operations, only the added/removed object is reported.
        // It’s assumed that all objects that come after the affected object are also moved, but these moves are not reported.
        if insertedObjects.count == 0 && deletedObjects.count == 0 {
            // A move is reported when the changed attribute on the object is one of the sort descriptors used in the fetch request.
            // An update of the object is assumed in this case, but no separate update message is sent to the delegate.
            for movedObject in movedObjects {
                var oldIndexPath: NSIndexPath? = nil
                var newIndexPath: NSIndexPath? = nil
                
                //
                let oldIndex = (oldFetchedObjects as NSArray).indexOfObject(movedObject)
                if oldIndex != NSNotFound {
                    for oldSectionIndex in oldSections.startIndex..<oldSections.endIndex {
                        let oldSection = oldSections[oldSectionIndex]
                        if NSLocationInRange(oldIndex, oldSection.range) {
                            let oldItemIndex = oldIndex - oldSection.range.location
                            oldIndexPath = NSIndexPath(forItem: oldItemIndex, inSection: oldSectionIndex)
                            break
                        }
                    }
                }
                
                //
                let newIndex = (newFetchedObjects as NSArray).indexOfObject(movedObject)
                if newIndex != NSNotFound {
                    for newSectionIndex in newSections.startIndex..<newSections.endIndex {
                        let newSection = newSections[newSectionIndex]
                        if NSLocationInRange(newIndex, newSection.range) {
                            let newItemIndex = newIndex - newSection.range.location
                            newIndexPath = NSIndexPath(forItem: newItemIndex, inSection: newSectionIndex)
                            break
                        }
                    }
                }
                
                //
                callControllerWillChangeContentIfNeeded()
                delegate.controller?(self, didChangeObject: movedObject, atIndexPath: oldIndexPath, forChangeType: .Move, newIndexPath: newIndexPath)
            }
            
            // An update is reported when an object’s state changes, but the changed attributes aren’t part of the sort keys. 
            for updatedObject in updatedObjects {
                let newIndex = (newFetchedObjects as NSArray).indexOfObject(updatedObject)
                if newIndex != NSNotFound {
                    for newSectionIndex in newSections.startIndex..<newSections.endIndex {
                        let newSection = newSections[newSectionIndex]
                        if NSLocationInRange(newIndex, newSection.range) {
                            let newItemIndex = newIndex - newSection.range.location
                            let newIndexPath = NSIndexPath(forItem: newItemIndex, inSection: newSectionIndex)
                            
                            callControllerWillChangeContentIfNeeded()
                            delegate.controller?(self, didChangeObject: updatedObject, atIndexPath: newIndexPath, forChangeType: .Update, newIndexPath: newIndexPath)
                            break
                        }
                    }
                }
            }
        }
        
        //
        if controllerWillChangeContentCalled {
            delegate.controllerDidChangeContent?(self)
        }
    }
    
}

// MARK: -

private class ALCSectionInfo: NSObject, ALCFetchedResultsSectionInfo {
    
    private unowned let fetchedResultsController: ALCFetchedResultsController
    private let range: NSRange

    @objc private let name: String?
    @objc private let indexTitle: String
    
    @objc private var numberOfObjects: Int {
        return self.range.length
    }
    
    @objc private var objects: [AnyObject] {
        if let fetchedObjects = self.fetchedResultsController.fetchedObjects {
            return Array(fetchedObjects[self.range.location..<self.range.location + self.range.length])
        }
        
        return [AnyObject]()
    }
    
    private init(fetchedResultsController: ALCFetchedResultsController, range: NSRange, name: String?, indexTitle: String) {
        self.fetchedResultsController = fetchedResultsController
        self.range = range
        
        self.name = name
        self.indexTitle = indexTitle
        
        super.init()
    }
    
}

// MARK: -

extension NSIndexPath {
    
    public convenience init!(forItem item: Int, inSection section: Int) {
        let indexes = [section, item]
        self.init(indexes: indexes, length: 2)
    }
    
    public convenience init!(forRow row: Int, inSection section: Int) {
        self.init(forItem: row, inSection: section)
    }
    
    public var section: Int { return self.indexAtPosition(0) }
    public var item: Int { return self.indexAtPosition(1) }
    public var row: Int { return self.item }
    
}

#endif