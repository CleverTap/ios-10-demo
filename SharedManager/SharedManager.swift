//
//  SharedManager.swift
//  demo10
//
//  Created by pwilkniss on 8/27/16.
//  Copyright © 2016 CleverTap. All rights reserved.
//

import Foundation
import UserNotifications

public enum MediaType: String {
    case image = "image"
    case gif = "gif"
    case video = "video"
    case audio = "audio"
    
    fileprivate static func attachmentOptions(forType type: MediaType) -> [String: Any?] {
        switch(type) {
        case .image:
            return [UNNotificationAttachmentOptionsThumbnailClippingRectKey: CGRect(x: 0.0, y: 0.0, width: 1.0, height: 0.50).dictionaryRepresentation]
        case .gif:
            return [UNNotificationAttachmentOptionsThumbnailTimeKey: 0]
        case .video:
            return [UNNotificationAttachmentOptionsThumbnailTimeKey: 0]
        case .audio:
            return [UNNotificationAttachmentOptionsThumbnailTimeKey: 0]
        }
    }
}

fileprivate protocol MediaAttachment {
    var fileIdentifier: String { get }
    var attachmentOptions: [String: Any?] { get }
    var mediaData: Data? { get }
}

fileprivate struct GIF: MediaAttachment {
    private var data: Data?
    
    init(withData data: Data) {
        self.data = data
    }

    var attachmentOptions: [String: Any?] {
        return MediaType.attachmentOptions(forType: .gif)
    }
    
    var fileIdentifier: String {
        return "image.gif"
    }
    
    var mediaData: Data? {
        return self.data
    }
}

extension UIImage: MediaAttachment {
    
    var attachmentOptions: [String: Any?] {
        return MediaType.attachmentOptions(forType: .image)
    }
    
    var fileIdentifier: String {
        return "image.png"
    }
    
    var mediaData: Data? {
        guard let data = UIImagePNGRepresentation(self) else {
            return nil
        }
        return data
    }
}

fileprivate extension UNNotificationAttachment {
    
    static func create<T: MediaAttachment>(media: T) -> UNNotificationAttachment? {
        let fileManager = FileManager.default
        let tmpSubFolderName = ProcessInfo.processInfo.globallyUniqueString
        let tmpSubFolderURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(tmpSubFolderName, isDirectory: true)
        do {
            try fileManager.createDirectory(at: tmpSubFolderURL, withIntermediateDirectories: true, attributes: nil)
            let fileIdentifier = media.fileIdentifier
            let fileURL = tmpSubFolderURL.appendingPathComponent(fileIdentifier)
            
            guard let data = media.mediaData else {
                return nil
            }
            
            try data.write(to: fileURL)
            return self.create(fileIdentifier: fileIdentifier, fileUrl: fileURL, options: media.attachmentOptions)
        } catch {
            print("error " + error.localizedDescription)
        }
        return nil
    }
    
    static func create(fileIdentifier: String, fileUrl: URL, options: [String : Any]? = nil) -> UNNotificationAttachment? {
        var n: UNNotificationAttachment?
        do {
            n = try UNNotificationAttachment(identifier: fileIdentifier, url: fileUrl, options: options)
        } catch {
            print("error " + error.localizedDescription)
        }
        return n
    }
}

private func localResourceURL(forUrlString url: String) -> URL? {
    if (url.hasPrefix("http")) { return nil }
    
    let components = url.components(separatedBy: ".")
    guard let fileName = components.first as String?, let ext = components.last as String? else {
        return nil
    }
    return SharedManager.bundle?.url(forResource: fileName, withExtension: ext)
}

private func imageFromLocalUrl(urlString url : String) -> UIImage? {
    guard let localURL = localResourceURL(forUrlString: url) else { return nil }
    return UIImage(contentsOfFile: localURL.path)
}

private func gifFromLocalUrl(urlString url : String) -> GIF? {
    guard let localURL = localResourceURL(forUrlString: url) else { return nil }
    
    do {
        let data = try Data(contentsOf: localURL)
        return GIF(withData: data)
    } catch {
        print("error " + error.localizedDescription)
        return nil
    }
}

private func loadImage(urlString:String, completion: @escaping (UIImage?, Error?) -> Void) {
    if let localImage = imageFromLocalUrl(urlString: urlString) {
        completion(localImage, nil)
        return
    }
    
    loadRemoteMedia(urlString: urlString, completion: { data, error in
        guard let _ = data else {
            completion(nil, error)
            return
        }
        completion(UIImage(data: data!), nil)
    })
}

private func loadGIF(urlString:String, completion: @escaping (GIF?, Error?) -> Void) {
    if let gif = gifFromLocalUrl(urlString: urlString) {
        completion(gif, nil)
        return
    }
    
    loadRemoteMedia(urlString: urlString, completion: { data, error in
        guard let _ = data else {
            completion(nil, error)
            return
        }
        completion(GIF(withData: data!), nil)
    })
}

private func loadRemoteMedia(urlString: String, completion: @escaping (Data?, Error?) -> Void) {
    let mediaUrl = URL(string: urlString)!
    URLSession.shared
        .dataTask(with: mediaUrl, completionHandler: { data, response, error in
            if (error != nil) { print(error?.localizedDescription) }
            completion(data, error)
        })
        .resume()
}

public struct SharedManager {
    
    static var bundle: Bundle? = Bundle(identifier: "com.clevertap.SharedManager")
    
    private var appGroupName: String
    
    private let userIdKey = "userId"
    
    private var sharedUserDefaults: UserDefaults?
    
    public var userId: String? {
        get {
          return self.retrieve(key: userIdKey)
        }
        set(newValue) {
            self.save(value: newValue!, forKey: userIdKey)
        }
    }
    
    private func save(value: String, forKey key: String) {
        sharedUserDefaults?.set(value, forKey: key)
        sharedUserDefaults?.synchronize()
    }
    
    private func retrieve(key: String) -> String? {
        return sharedUserDefaults?.object(forKey: key) as? String
    }
    
    public init(forAppGroup appGroupName: String) {
        self.appGroupName = appGroupName
        sharedUserDefaults = UserDefaults(suiteName: appGroupName)
        sharedUserDefaults?.synchronize()
    }
    
    public func createNotificationAttachment(forMediaType mediaType: MediaType, withUrl url: String, completionHandler: ((UNNotificationAttachment?) -> Void)) {
        switch(mediaType) {
        case .image:
            loadImage(urlString: url, completion: { image, error in
                if (image != nil) {
                    if let attachment = UNNotificationAttachment.create(media: image!) {
                        completionHandler(attachment)
                        return
                    }
                }
                completionHandler(nil)
            })
            
        case .gif:
            loadGIF(urlString: url, completion: { gif, error in
                if (gif != nil) {
                    if let attachment = UNNotificationAttachment.create(media: gif!) {
                        completionHandler(attachment)
                        return
                    }
                }
                completionHandler(nil)
            })
            
        case .video:
            break
            
        case .audio:
            break
        }
    }
}