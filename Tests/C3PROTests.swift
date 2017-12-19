//
//  C3PROTests.swift
//  C3PROTests
//
//  Created by Pascal Pfiffner on 4/20/15.
//  Copyright (c) 2015 Boston Children's Hospital. All rights reserved.
//

import UIKit
import XCTest
import C3PRO
import SMART

class C3PROTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testInit() {
        //let hostname = "jamess-mbp-2.j4home.net"
        //let hostname = "jamess-mbp-2.local"
        let hostname = "localhost"
        //     let client = Client(baseURL: URL(string: "https://api.io")!, settings: ["cliend_id": "client", "redirect": "oauth://callback"])
        //     XCTAssertTrue(client.server.baseURL.absoluteString == "https://api.io/")
        
        let my_auth = [
            "client_name": "My Awesome App",
            //"client_id": "MY Client ID",
            "authorize_uri": "https://\(hostname):8081/c3pro/auth",
            "registration_uri": "https://\(hostname):8081/c3pro/register",
            "authorize_type": "client_credentials",
            ] as OAuth2JSON
        let queue = DataQueue(baseURL: URL(string: "https://\(hostname):8081/c3pro/")!, auth: my_auth)
        
        //
        // DANGER ... DEBUG URL Session Delegate allows man-in-the-middle attacks (using self-signed certs or bogus Certificate Authorities).
        // using for now, because convenient for testing only.
        //
        queue.sessionDelegate = OAuth2DebugURLSessionDelegate(host: hostname)
        //queue.sessionDelegate.encode(to: <#T##Encoder#>)
        
        
        
        queue.logger = OAuth2DebugLogger(OAuth2LogLevel.trace)
        queue.onBeforeDynamicClientRegistration = { url in
            let registration = OAuth2DynRegAppStore()
            registration.sandbox = true
            registration.overrideAppReceipt("your apple-supplied app purchase receipt")
            registration.extraHeaders = [
                "Antispam" : "myantispam",
                ] as OAuth2StringDict
            return registration
        }
        //queue.re
        let exp = expectation(description: "auth happened already")
        let client = Client(server: queue);
        client.authorize(callback: { (patient: Patient?, error: Error?) in
            queue.logger?.trace(filename: "C3PROTests", msg: ">>>>>>>>> in authorize callback, patient=\(patient), error=\(error)")
            if let p = patient {
                print(p)
            }
            if let e = error {
                print(e)
            }
            exp.fulfill()
            return
        })
        queue.logger?.trace(filename: "C3PROTests", msg: ">>>>>> BEFORE wait for authorize()")
        waitForExpectations(timeout: 15)
        queue.logger?.trace(filename: "C3PROTests", msg: ">>>>>> AFTER wait for authorize()")
        XCTAssertTrue(client.server.baseURL.absoluteString == "https://\(hostname):8081/c3pro/")
        client.ready(callback: {(error) in
            queue.logger?.trace(filename: "C3PROTests", msg: ">>>>>>> inside client.ready() error callback, error=\(error)")
            if error != nil {
                print (error.debugDescription)
            }
        })
        
        //        //XCTAssertNil(client.auth.clientId, "clientId will only be queryable once we have an OAuth2 instance")
        client.ready { error in
            XCTAssertNil(error)
        }
    }

    
//    func testExample() {
//        let url = URL(string: "http://localhost:8081/c3pro/register")!
//        var request = URLRequest(url: url)
//        let antispam = "myantispam"
//        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
//        request.setValue("application/json", forHTTPHeaderField: "Accept")
//        request.setValue(antispam, forHTTPHeaderField: "Antispam")
//        request.httpMethod = "POST"
//        dic = ["registr]
//        let jsonData = try JSONSerialization.data(withJSONObject: dic, options: .prettyPrinted)
//        if let dictionary = jsonWithObjectRoot as? [String: any] {
//            if let
//        }
//        let postString = "{"
//        request.httpBody = postString.data(using: .utf8)
//        /*
//          {
//           "client_id":"1f67bb6e-083b-4222-90b0-1c407a252fa5",
//           "client_secret":"E8UA43R5DdYr582nTCGPJBn8QG5wi+MCy5hoyKMdScAA5rZaitOxykSqW1gIi+HInrVxK4N3IV62O3Lu7wGRQ\u003d\u003d",
//           "grant_types":["client_credentials"],
//           "token_endpoint_auth_method":"client_secret_basic"
//          }
//        */
//        //let smart = Client(baseURL: "http://localhost:8081", settings: OAuth2JSON)
//        // This is an example of a functional test case.
//        XCTAssert(true, "Pass")
//    }
}
