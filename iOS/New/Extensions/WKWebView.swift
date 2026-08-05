//
//  WKWebView.swift
//  Aidoku
//
//  Created by Skitty on 5/21/25.
//

import WebKit

extension WKWebView {
    func getCookies(for domain: String? = nil) async -> [String: String]  {
        await withCheckedContinuation { continuation in
            configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                var cookieDict = [String: String]()
                for cookie in cookies {
                    if let domain {
                        if cookie.domain.contains(domain) {
                            cookieDict[cookie.name] = cookie.value
                        }
                    } else {
                        cookieDict[cookie.name] = cookie.value
                    }
                }
                continuation.resume(returning: cookieDict)
            }
        }
    }

    func getLocalStorage(keys: [String]) async -> [String: String] {
        let keysData = (try? JSONSerialization.data(withJSONObject: keys)) ?? Data("[]".utf8)
        let keysJson = String(data: keysData, encoding: .utf8) ?? "[]"
        // In addition to the requested keys, scan localStorage for anything that looks like
        // an auth token, since some sites store it under a key we don't know about ahead of time.
        // Also unwrap nested JSON blobs (`{"token":"..."}`) into a flat `token` entry.
        let js = """
        (function() {
            var result = {};
            function put(key, value) {
                if (value == null) { return; }
                var s = (typeof value === 'string') ? value : String(value);
                if (!s) { return; }
                result[key] = s;
                if (s.length >= 2 && s.charAt(0) === '{' && s.charAt(s.length - 1) === '}') {
                    try {
                        var obj = JSON.parse(s);
                        if (obj && typeof obj === 'object') {
                            var nested = ['token','access_token','accessToken','auth_token','authToken','jwt'];
                            for (var n = 0; n < nested.length; n++) {
                                var nk = nested[n];
                                if (typeof obj[nk] === 'string' && obj[nk]) {
                                    result[nk] = obj[nk];
                                }
                            }
                            if (obj.state && typeof obj.state === 'object') {
                                for (var n2 = 0; n2 < nested.length; n2++) {
                                    var nk2 = nested[n2];
                                    if (typeof obj.state[nk2] === 'string' && obj.state[nk2]) {
                                        result[nk2] = obj.state[nk2];
                                    }
                                }
                            }
                        }
                    } catch (e) {}
                }
            }
            var keys = \(keysJson);
            for (var i = 0; i < keys.length; i++) {
                put(keys[i], localStorage.getItem(keys[i]));
            }
            try {
                for (var i = 0; i < localStorage.length; i++) {
                    var k = localStorage.key(i);
                    if (!k || Object.prototype.hasOwnProperty.call(result, k)) { continue; }
                    var lower = k.toLowerCase();
                    if (lower.indexOf('token') !== -1 || lower.indexOf('auth') !== -1 || lower.indexOf('persist') !== -1) {
                        put(k, localStorage.getItem(k));
                    }
                }
            } catch (e) {}
            return result;
        })();
        """
        do {
            let result = try await evaluateJavaScript(js)
            return Self.stringDictionary(from: result)
        } catch {
            return [:]
        }
    }

    /// `evaluateJavaScript` returns bridged `NSDictionary`/`NSNumber` values, so a direct
    /// `as? [String: String]` cast frequently fails even when the JS object only contains strings.
    private static func stringDictionary(from value: Any?) -> [String: String] {
        if let dict = value as? [String: Any] {
            var result = [String: String]()
            for (key, val) in dict {
                if let s = val as? String {
                    result[key] = s
                } else if let n = val as? NSNumber {
                    result[key] = n.stringValue
                }
            }
            return result
        }
        if let dict = value as? [AnyHashable: Any] {
            var result = [String: String]()
            for (key, val) in dict {
                guard let keyString = key as? String else { continue }
                if let valueString = val as? String {
                    result[keyString] = valueString
                } else if let n = val as? NSNumber {
                    result[keyString] = n.stringValue
                }
            }
            return result
        }
        return [:]
    }
}
