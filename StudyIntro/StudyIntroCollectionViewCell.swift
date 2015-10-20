//
//  StudyIntroCollectionViewCell.swift
//  C3PRO
//
//  Created by Pascal Pfiffner on 20/10/15.
//  Copyright © 2015 Boston Children's Hospital. All rights reserved.
//

import UIKit


public class StudyIntroWelcomeCell: UICollectionViewCell {
	
	@IBOutlet public var image: UIImageView?
	
	@IBOutlet public var titleLabel: UILabel?
	
	@IBOutlet public var subtitleLabel: UILabel?
	
	@IBOutlet public var consentButton: UIButton?
	
	@IBOutlet public var videoButton: UIButton?
	
	@IBOutlet public var swipeLabel: UILabel?
	
	public var onConsentTap: (Void -> Void)?
	public var onVideoTap: ((name: String) -> Void)?
	
	public var item: StudyIntroWelcomeItem? {
		didSet {
			setupCellWithItem(item)
		}
	}
	
	public override func prepareForReuse() {
		super.prepareForReuse()
		titleLabel?.numberOfLines = (bounds.size.height > 280.0) ? 0 : 1;			// to force one line on iPhone 4S
	}
	
	func setupCellWithItem(item: StudyIntroWelcomeItem?) {
		if let item = item {
			if let logo = item.logoName {
				image?.image = UIImage(named: logo)
			}
			titleLabel?.text = item.title
			subtitleLabel?.text = item.subtitle
		}
		videoButton?.enabled = (nil != item?.videoName)
		videoButton?.hidden = (nil == item?.videoName)
	}
	
	
	// MARK: - Actions
	
	@IBAction func showConsent() {
		if let exec = onConsentTap {
			exec()
		}
		else {
			chip_warn("Have not yet assigned `onConsentTap`")
		}
	}
	
	@IBAction func showVideo() {
		if let exec = onVideoTap, let video = item?.videoName {
			exec(name: video)
		}
		else {
			chip_warn("Have not assigned `onVideoTap` or the welcome item does not define `videoName`")
		}
	}
}


public class StudyIntroVideoCell: UICollectionViewCell {

	@IBOutlet public var titleLabel: UILabel?
	
	@IBOutlet public var videoButton: UIButton?
	
	@IBOutlet public var videoMessage: UILabel?
	
	public var onVideoTap: ((name: String) -> Void)?
	
	public var item: StudyIntroVideoItem? {
		didSet {
			setupCellWithItem(item)
		}
	}
	
	func setupCellWithItem(item: StudyIntroVideoItem?) {
		if let item = item {
			videoButton?.setImage(UIImage(named: item.videoIconName), forState: .Normal)
		}
		videoButton?.enabled = (nil != item?.videoName)
	}
	
	@IBAction func showVideo() {
		if let exec = onVideoTap, let video = item?.videoName {
			exec(name: video)
		}
		else {
			chip_warn("Have not assigned `onVideoTap` or the video item does not define `videoName`")
		}
	}
}


public class StudyIntroHTMLCell: UICollectionViewCell, UIWebViewDelegate {
	
	@IBOutlet public var webView: UIWebView?
	
	public var item: StudyIntroHTMLItem? {
		didSet {
			setupCellWithItem(item)
		}
	}
	
	func setupCellWithItem(item: StudyIntroHTMLItem?) {
		if let url = item?.url {
			webView?.loadRequest(NSURLRequest(URL: url))
		}
	}
	
	
	public func webView(webView: UIWebView, shouldStartLoadWithRequest request: NSURLRequest, navigationType: UIWebViewNavigationType) -> Bool {
		if .LinkClicked == navigationType, let url = request.URL {
			return !UIApplication.sharedApplication().openURL(url)
		}
		return true
	}
	
	public func webViewDidFinishLoad(webView: UIWebView) {
		webView.stringByEvaluatingJavaScriptFromString("document.documentElement.style.webkitUserSelect=\"none\"")		// disable text selection
	}
}

