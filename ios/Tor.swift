import Foundation

// Trust SSLs even if invalid
extension Tor: URLSessionDelegate {
  public func urlSession(
    _ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (
      URLSession.AuthChallengeDisposition, URLCredential?
    ) -> Void
  ) {
    //Trust the certificate even if not valid
    let urlCredential = URLCredential(
      trust: challenge.protectionSpace.serverTrust!)
    completionHandler(.useCredential, urlCredential)
  }
}

extension DispatchQueue {
  static func background(
    delay: Double = 0.0, background: (() -> Void)? = nil,
    completion: (() -> Void)? = nil
  ) {
    DispatchQueue.global(qos: .background).async {
      background?()
      if let completion = completion {
        DispatchQueue.main.asyncAfter(
          deadline: .now() + delay,
          execute: {
            completion()
          })
      }
    }
  }
}

class ObserverSwift {
  public let onSuccess: ((String) -> Void)
  public let onError: ((String) -> Void)
  init(
    onSuccess: @escaping ((String) -> Void),
    onError: @escaping ((String) -> Void), target: String
  ) {
    self.onSuccess = onSuccess
    self.onError = onError
  }
}

@objc(Tor)
class Tor: RCTEventEmitter {
  var service: OpaquePointer? = nil
  var proxySocksPort: UInt16? = nil
  var starting: Bool = false
  var streams: [String: OpaquePointer] = [:]
  var hasLnser = false
  var clienTimeout: TimeInterval = 60

  func getProxiedClient(
    headers: NSDictionary?, socksPort: UInt16, trustInvalidSSL: Bool = false
  ) -> URLSession {
    let config = URLSessionConfiguration.default
    config.requestCachePolicy =
      URLRequest.CachePolicy.reloadIgnoringLocalCacheData
    config.connectionProxyDictionary = [AnyHashable: Any]()
    config.connectionProxyDictionary?[kCFNetworkProxiesHTTPEnable as String] = 1
    config.connectionProxyDictionary?[
      kCFStreamPropertySOCKSProxyHost as String] = "127.0.0.1"
    config.connectionProxyDictionary?[
      kCFStreamPropertySOCKSProxyPort as String] = socksPort
    config.connectionProxyDictionary?[kCFProxyTypeSOCKS as String] = 1
    config.timeoutIntervalForRequest = clienTimeout
    config.timeoutIntervalForResource = clienTimeout

    if let headersPassed = headers {
      config.httpAdditionalHeaders = headersPassed as? [AnyHashable: Any]
    }
    if trustInvalidSSL {
      return URLSession.init(
        configuration: config, delegate: self, delegateQueue: nil)
    } else {
      return URLSession.init(
        configuration: config, delegate: nil,
        delegateQueue: OperationQueue.current)
    }
  }

  func resolveObjResp(
    data: Data, resp: HTTPURLResponse,
    resolve: @escaping RCTPromiseResolveBlock,
    reject: @escaping RCTPromiseRejectBlock
  ) {
    let jsonObject: NSMutableDictionary = NSMutableDictionary()
    jsonObject.setValue(data.base64EncodedString(), forKey: "b64Data")
    jsonObject.setValue(resp.mimeType, forKey: "mimeType")
    jsonObject.setValue(resp.allHeaderFields, forKey: "headers")
    jsonObject.setValue(resp.statusCode, forKey: "respCode")
    // parse json if that's what we have
    if let mimeType = resp.mimeType {
      if mimeType == "application/json" || mimeType == "application/javascript"
      {
        do {
          let json = try JSONSerialization.jsonObject(
            with: data, options: .allowFragments)
          jsonObject.setValue(json, forKey: "json")
        } catch {
          print("prepareObjResp errorParsingJson!", error)
        }
      }
    }

    if 200...299 ~= resp.statusCode {
      resolve(jsonObject as NSObject)
    } else {
      var msg: String? = nil
      if let errorMessage = String(data: data, encoding: .utf8) {
        msg = errorMessage
      }
      reject(
        "TOR.REQUEST", "Resp Code: \(resp.statusCode) : \(msg)",
        NSError.init(
          domain: "TOR.REQUEST", code: resp.statusCode, userInfo: ["data": msg])
      )
    }
  }

  @objc(request:method:body:headers:trustInvalidCert:resolver:rejecter:)
  func request(
    url: String, method: String, body: String, headers: NSDictionary,
    trustInvalidCert: Bool, resolve: @escaping RCTPromiseResolveBlock,
    reject: @escaping RCTPromiseRejectBlock
  ) {

    if service == nil {
      reject(
        "TOR.SERVICE", "Tor Service NOT Running. Call `startDaemon` first.",
        NSError.init(domain: "TOR.DAEMON", code: 99))
      return
    }

    let session = getProxiedClient(
      headers: headers, socksPort: proxySocksPort!,
      trustInvalidSSL: trustInvalidCert)
    guard let _url = URL(string: url) else {
      reject(
        "TOR.URL", "Could not parse url", NSError.init(domain: "TOR", code: 404)
      )
      return
    }

    do {
      switch method {
      case "get":
        session.dataTask(with: _url) { data, resp, error in
          guard let dataResp = data, error == nil, let respData = resp else {
            reject("TOR.NETWORK.GET", error?.localizedDescription, error)
            return
          }
          self.resolveObjResp(
            data: dataResp, resp: respData as! HTTPURLResponse,
            resolve: resolve, reject: reject)
        }.resume()
      case "delete":
        var request = URLRequest(url: _url)
        request.httpMethod = "DELETE"
        session.dataTask(with: request) { data, resp, error in
          guard let dataResp = data, error == nil, let respData = resp else {
            reject("TOR.NETWORK.DELETE", error?.localizedDescription, error)
            return
          }
          self.resolveObjResp(
            data: dataResp, resp: respData as! HTTPURLResponse,
            resolve: resolve, reject: reject)

        }.resume()
      case "post":
        var request = URLRequest(url: _url)
        request.httpMethod = "POST"

        var data = body.data(using: .utf8)
        let contentType:String? = headers["Content-Type"] as? String
        if contentType == "application/octet-stream" {
          data = Data(base64Encoded: data!)
        }

        session.uploadTask(with: request, from: data) { data, resp, error in
          guard let dataResp = data, let respData = resp, error == nil else {
            reject("TOR.NETWORK.POST", error?.localizedDescription, error)
            return
          }
          self.resolveObjResp(
            data: dataResp, resp: respData as! HTTPURLResponse,
            resolve: resolve, reject: reject)
        }.resume()

      default:
        throw NSError.init(domain: "TOR.REQUEST_METHOD", code: 400)
      }

    } catch {
      reject("TOR.REQUEST", error.localizedDescription, error)
    }
  }

  @objc(startDaemon:clientTimeoutSec:resolver:rejecter:)
  func startDaemon(
    timeoutMs: NSNumber, clientTimeoutSec: NSNumber,
    resolve: @escaping RCTPromiseResolveBlock,
    reject: @escaping RCTPromiseRejectBlock
  ) {
    if service != nil || starting {
      reject(
        "TOR.START", "Tor Service Already Running. Call `stopDaemon` first.",
        NSError.init(domain: "TOR.START", code: 01))
      return
    }
    clienTimeout = clientTimeoutSec.doubleValue
    starting = true
    do {

      let temporaryDirectoryURL = URL(
        fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      // FIXME pass this and check if avalible
      let socksPort: UInt16 = 19032
      // this gives file:///Users/.../tmp/ so we remove the file:// prefix and trailing slash
      let path = String(
        temporaryDirectoryURL.absoluteString.dropFirst(7).dropLast())

      // Rust will start Tor daemon thread and block until boostrapped, so run as dispatched async task so not to block this thread
      DispatchQueue.background(
        background: {
          defer {
            self.starting = false
          }
          // FIXME here make the timeout a param
          // better way to automatically have the JS promise handle a fail ?
          let call_result = get_owned_TorService(
            path, socksPort, timeoutMs.uint64Value
          ).pointee
          switch call_result.message.tag {
          case Success:
            self.service = Optional.some(call_result.result)
            self.proxySocksPort = socksPort
            resolve(socksPort)
            return
          case Error:
            // Convert RustByteSlice to String
            if let error_body = call_result.message.error {
              let error_string = String.init(cString: error_body)
              reject(
                "TOR.START", error_string, NSError.init(domain: "TOR", code: 0))
            } else {
              reject(
                "TOR.START", "Unknown daemon startup error",
                NSError.init(domain: "TOR", code: 99))
            }
            return
          default:
            reject(
              "TOR.START", "unknown startup result",
              NSError.init(domain: "TOR", code: 99))
            return
          }
        },
        completion: {
        })
    }
  }

  @objc(getDaemonStatus:rejecter:)
  func getDaemonStatus(
    resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock
  ) {
    guard let daemon = service else {
      if starting {
        resolve("STARTING")
      } else {
        resolve("NOTINIT")
      }
      return
    }

    if let status = get_status_of_owned_TorService(daemon) {
      defer {
        destroy_cstr(status)
      }
      let status_string = String.init(cString: status)
      resolve(status_string)
    } else {
      reject("TOR.STATUS", "UNKNOWN", NSError.init(domain: "TOR", code: 99))
    }

  }

  @objc(stopDaemon:rejecter:)
  func stopDaemon(
    resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock
  ) {
    if let hasSevice = service {
      // if we have streams, shut them down
      for key in streams.keys {
        if let stream = streams[key] {
          // set it here in case eof callback gets called
          // while looping
          streams[key] = nil
          tcp_stream_destroy(stream)
        }
      }
      shutdown_owned_TorService(hasSevice)
      service = nil
      proxySocksPort = nil
    }
    resolve(true)
  }

  override func startObserving() {
    self.hasLnser = true
  }
  override func stopObserving() {
    self.hasLnser = false
  }

  // FIXME here it needs to support, so i guess we can use
  override func supportedEvents() -> [String]! {
    ["torTcpStreamData", "torTcpStreamError"]
  }

  @objc(startTcpConn:timeoutMs:resolver:rejecter:)
  func startTcpConn(
    target: String, timeoutMs: NSNumber, resolve: RCTPromiseResolveBlock,
    reject: RCTPromiseRejectBlock
  ) {
    guard let socksProxy = self.proxySocksPort else {
      reject(
        "TOR.TCPCONN.startTcpConn",
        "SocksProxy not detected, make sure Tor is started",
        NSError.init(domain: "TOR", code: 99))
      return
    }

    let uuid = UUID().uuidString

    let call_result = tcp_stream_start(
      target, "127.0.0.1:\(socksProxy)", timeoutMs.uint64Value
    ).pointee
    switch call_result.message.tag {
    case Success:
      let stream = call_result.result
      self.streams[uuid] = stream
      // Create swift observer wrapper to store context
      let observerWrapper = ObserverSwift(
        onSuccess: { (data) in
          self.sendEvent(withName: "torTcpStreamData", body: "\(uuid)||\(data)")
        },
        onError: { (data) in
          // On Eof destrory stream and remove from map
          // TODO update this when streaming streams
          if data == "EOF" {
            guard let stream = self.streams[uuid] else {
              print("Note: EOF but stream already destroyed, returning...")
              return
            }
            tcp_stream_destroy(stream)
            self.streams[uuid] = nil
          } else if data.contains("NotConnected") {
            guard self.streams[uuid] != nil else {
              print("Note: EOF but stream already destroyed, returning...")
              return
            }
            // Stream pointer could be already delocated from rust side here
            // so don't try to destory it just remove it from map of references.
            // Worst case we create a new one and the memory leak gets recycled
            // when app restarts
            // TODO way to better coordinate this.
            // tcp_stream_destroy(stream);
            self.streams[uuid] = nil
          } else {
            print("Got observerWrapper event but not EOF", data)

          }
          self.sendEvent(
            withName: "torTcpStreamError", body: "\(uuid)||\(data)")
        }, target: target)
      // Prepare pointer to context and observer callbacks as Retained
      let owner = UnsafeMutableRawPointer(
        Unmanaged.passRetained(observerWrapper).toOpaque())

      let onSuccess:
        @convention(c) (UnsafeMutablePointer<Int8>?, UnsafeRawPointer?) -> Void =
          { (data, context) in
            // take unretained so we don't clear it
            let obv = Unmanaged<ObserverSwift>.fromOpaque(context!)
              .takeUnretainedValue()
            obv.onSuccess(String(cString: data!))
            destroy_cstr(data)

          }
      let onError:
        @convention(c) (UnsafeMutablePointer<Int8>?, UnsafeRawPointer?) -> Void =
          { (data, context) in
            let obv = Unmanaged<ObserverSwift>.fromOpaque(context!)
              .takeUnretainedValue()
            obv.onError(String(cString: data!))
            destroy_cstr(data)
          }
      let obv = Observer(context: owner, on_success: onSuccess, on_err: onError)
      tcp_stream_on_data(stream, obv)
      resolve(uuid)
      return
    case Error:
      // Convert RustByteSlice to String
      if let error_body = call_result.message.error {
        let error_string = String.init(cString: error_body)
        reject(
          "TOR.TCPCONN.startTcpConn", error_string,
          NSError.init(domain: "TOR", code: 0))
      } else {
        reject(
          "TOR.TCPCONN.startTcpConn", "Unknown tcpStream startup error",
          NSError.init(domain: "TOR", code: 99))
      }
      return
    default:
      reject(
        "TOR.startTcpConn", "unknown startup result",
        NSError.init(domain: "TOR", code: 99))
      return
    }

  }

  @objc(sendTcpConnMsg:msg:timeoutSec:resolver:rejecter:)
  func sendTcpConnMsg(
    target: String, msg: String, timeoutSec: NSNumber,
    resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock
  ) {
    guard self.service != nil else {
      reject(
        "TOR.TCPCONN.sendTcpConnMsg",
        "Service not detected, make sure Tor is started",
        NSError.init(domain: "TOR", code: 99))
      return
    }
    guard let stream = self.streams[target] else {
      reject(
        "TOR.TCPCONN.sendTcpConnMsg", "Stream not detected",
        NSError.init(domain: "TOR", code: 99))
      return
    }
    let result = tcp_stream_send_msg(stream, msg, timeoutSec.uint64Value)
      .pointee
    switch result.tag {
    case Success:
      resolve(true)
      return
    case Error:
      if let error_body = result.error {
        let error_string = String.init(cString: error_body)
        reject(
          "TOR.TCPCONN.sendTcpConnMsg", error_string,
          NSError.init(domain: "TOR", code: 0))
      } else {
        reject(
          "TOR.TCPCONN.sendTcpConnMsg", "Unknown tcpStream startup error",
          NSError.init(domain: "TOR", code: 99))
      }
      return
    default:
      reject(
        "TOR.TCPCONN.sendTcpConnMsg", "unknown tcp send message result",
        NSError.init(domain: "TOR", code: 99))
      return
    }
  }

  @objc(stopTcpConn:resolver:rejecter:)
  func stopTcpConn(
    target: String, resolve: RCTPromiseResolveBlock,
    reject: RCTPromiseRejectBlock
  ) {
    guard let stream = self.streams[target] else {
      reject(
        "TOR.TCPCONN.stopTcpConn", "Stream not detected",
        NSError.init(domain: "TOR", code: 99))
      return
    }
    self.streams[target] = nil
    tcp_stream_destroy(stream)
    resolve(true)
  }
}
