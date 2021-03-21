//
//  VideoPlayerViewController.swift
//  FairplayDemo
//
//  Created by Mostafa Mohamed on 2/23/20.
//

import UIKit
import AVKit

fileprivate let streamURL = ""
fileprivate let certificateURL = ""
fileprivate let jwt = ""
class VideoPlayerViewController: UIViewController {
  
  @IBOutlet private weak var playerView: UIView!
  var player: AVPlayer!
  var certificate: Data?
  var licenseURL = ""
  override func viewDidLoad() {
    //1. fetch drm certificate
    self.requestApplicationCertificate { (cer, error) in
      if error == nil && cer != nil {
        self.certificate = cer
        if let url = URL(string: streamURL) {
          DispatchQueue.main.async {
            //2. Create AVPlayer object
            let asset = AVURLAsset(url: url)
            let queue = DispatchQueue(label: "LicenseGetQueue")
            asset.resourceLoader.setDelegate(self, queue: queue)
            let playerItem = AVPlayerItem(asset: asset)
            self.player = AVPlayer(playerItem: playerItem)
            //3. Create AVPlayerLayer object
            let playerLayer = AVPlayerLayer(player: self.player)
            playerLayer.frame = self.playerView.bounds //bounds of the view in which AVPlayer should be displayed
            playerLayer.videoGravity = .resizeAspect
            
            //4. Add playerLayer to view's layer
            self.playerView.layer.addSublayer(playerLayer)
            //5. Play Video
            self.player.play()
          }
        }
      } else {
        print("📜", #function, "Unable to fetch the certificate.")
      }
    }
  }
  
  
  func requestApplicationCertificate(with completion: @escaping (Data? , Error?) -> ()) {
    // This function gets the FairPlay application certificate, expected in DER format, from the
    // configured URL. In general, the logic to obtain the certificate is up to the playback app
    // implementers. Implementers should use their own certificate, received from Apple upon request.
    
    let configuration = URLSessionConfiguration.default
    let session = URLSession(configuration: configuration)
    guard let url = URL(string: certificateURL) else {return}
    session.dataTask(with: url, completionHandler: { data, response, error in
      
      completion(data, error)
    }).resume()
  }
  
  func requestContentKeyAndLeaseExpiryfromKeyServerModule(withRequestBytes requestBytes: Data?, completion: @escaping (Data?, Error?) -> ()) {
    let ckcURL = URL(string: licenseURL)!
    var request = URLRequest(url: ckcURL)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
    var requestBodyComponent = URLComponents()
    requestBodyComponent.queryItems = [URLQueryItem(name: "spc", value: requestBytes?.base64EncodedString())]
    request.httpBody = requestBodyComponent.query?.data(using: .utf8)
    let session = URLSession(configuration: URLSessionConfiguration.default)
    session.dataTask(with: request) { data, response, error in
      if let data = data, var responseString = String(data: data, encoding: .utf8) {
        responseString = responseString.replacingOccurrences(of: "<ckc>", with: "").replacingOccurrences(of: "</ckc>", with: "")
        let ckcData = Data(base64Encoded: responseString)
        completion(ckcData, error)
      } else {
        completion(nil, error)
      }
    }.resume()
  }
}


extension VideoPlayerViewController: AVAssetResourceLoaderDelegate {
  func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
    guard let dataRequest = loadingRequest.dataRequest else {return false}
    // 6: Request the Server Playback Context from OS
    // To obtain the license request (Server Playback Context or SPC in Apple's terms), we call
    // .streamingContentKeyRequestData(forApp:contentIdentifier:options:)
    // using the information we obtained earlier.
    licenseURL = (loadingRequest.request.url?.absoluteString ?? "").replacingOccurrences(of: "skd", with: "https")
    guard
      let contentIdData = (loadingRequest.request.url?.host ?? "").data(using: String.Encoding.utf8),
      let spcData = try? loadingRequest.streamingContentKeyRequestData(forApp: certificate!, contentIdentifier: contentIdData, options: nil) else {
      loadingRequest.finishLoading(with: NSError(domain: "com.icapps.error", code: -3, userInfo: nil))
      print("🔑", #function, "Unable to read the SPC data.")
      return false
    }
    
    // 7: Request CKC
    // Send the license request to the license server. The encrypted license response (Content Key
    // Context or CKC in Apple's terms) will contain the content key and associated playback policies.
    self.requestContentKeyAndLeaseExpiryfromKeyServerModule(withRequestBytes: spcData) { (ckc, error) in
      if error == nil && ckc != nil {
        // The CKC is correctly returned and is now send to the `AVPlayer` instance so we
        // can continue to play the stream.
        dataRequest.respond(with: ckc!)
        loadingRequest.contentInformationRequest?.contentType = AVStreamingKeyDeliveryContentKeyType
        loadingRequest.finishLoading()
      } else {
        print("🔑", #function, "Unable to fetch the CKC.")
        loadingRequest.finishLoading(with: error)
      }
    }
    
    return true
  }
}
