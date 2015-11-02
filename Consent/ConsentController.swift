//
//  ConsentController.swift
//  C3PRO
//
//  Created by Pascal Pfiffner on 5/20/15.
//  Copyright (c) 2015 Boston Children's Hospital. All rights reserved.
//

import Foundation
import SMART
import ResearchKit


public typealias ConsentSigningCallback = ((contract: Contract, patient: Patient, error: NSError?) -> Void)

/// Name of notification sent when the user completes and agrees to consent.
public let C3UserDidConsentNotification = "C3UserDidConsentNotification"

/// Name of notification sent when the user cancels or declines to consent.
public let C3UserDidDeclineConsentNotification = "C3UserDidDeclineConsentNotification"


let CHIPConsentingErrorKey = "CHIPConsentingError"


/**
	Struct to hold various options for consenting.
 */
public struct ConsentTaskOptions
{
	public var askForSharing = true
	
	var shareTeamName = "the research team"
	
	/// Name of a bundled HTML file (without extension) that contains more information about data sharing.
	public var shareMoreInfoDocument = "Consent_sharing"
	
	/// Optional: name of a bundled HTML file (without extension) that contains the full consent document for review.
	public var reviewConsentDocument: String? = nil
	
	/// Shown when the user taps agree and she needs to confirm that she is in agreement.
	public var reasonForConsent = NSLocalizedString("By agreeing you confirm that you read the consent and that you wish to take part in this research study.", comment: "")
	
	public init() {  }
}


/**
    Controller to capture consent in a FHIR Contract resource.
 */
public class ConsentController
{
	/// The contract to be signed; if nil when signing, a new instance will be created.
	public final var contract: Contract?
	
	public var options = ConsentTaskOptions()
	
	var deidentifier: DeIdentifier?
	
	var consentDelegate: ConsentTaskViewControllerDelegate?
	
	var onUserDidConsent: ((controller: ORKTaskViewController) -> Void)?
	
	var onUserDidDeclineConsent: ((controller: ORKTaskViewController) -> Void)?
	
	/**
	Designated initializer.
	
	You can optionally supply the name of a bundled JSON file (without extension) that represents a serialized FHIR Contract resource.
	*/
	public init(bundledContract: String? = nil) {
		if let name = bundledContract {
			do {
				contract = try NSBundle.mainBundle().fhir_bundledResource(name) as? Contract
			}
			catch let error {
				chip_warn("failed to read bundled Contract resource: \(error)")
			}
		}
	}
	
	
	// MARK: - Eligibility
	
	/**
	Instantiates a controller prompting the user to press “Start Eligibility”. Pressing that button pushes an EligibilityCheckViewController
	onto the navigation stack, which carries the actual eligibility criteria.
	
	- parameter config: An optional `StudyIntroConfiguration` instance that carries custom eligible/ineligible texts
	- parameter onStartConsent: The block to execute when all eligibility criteria are met and the participant wants to start consent. Leave
	    nil to automatically present (and dismiss) the consent task view controller that will be returned by `consentViewController()`.
	*/
	public func eligibilityStatusViewController(config: StudyIntroConfiguration? = nil, onStartConsent: ((viewController: EligibilityCheckViewController) -> Void)? = nil) -> EligibilityStatusViewController {
		let check = EligibilityStatusViewController()
		check.title = NSLocalizedString("Eligibility", comment: "")
		check.titleText = NSLocalizedString("Let's see if you may take part in this study", comment: "")
		check.subText = NSLocalizedString("Tap the button below to begin the eligibility process", comment: "")
		check.actionButtonTitle = NSLocalizedString("Start Eligibility", comment: "")
		
		// the actual eligibility check view controller; configure to present on check's navigation controller if no block is provided
		let elig = EligibilityCheckViewController(style: .Grouped)
		if let onStartConsent = onStartConsent {
			elig.onStartConsent = onStartConsent
		}
		else {
			elig.onStartConsent = { viewController in
				if let navi = viewController.navigationController {
					let consent = self.consentViewController(
						onUserDidConsent: { controller in
							navi.dismissViewControllerAnimated(true, completion: nil)
						},
						onUserDidDecline: { controller in
							navi.popToRootViewControllerAnimated(false)
							navi.dismissViewControllerAnimated(true, completion: nil)
						}
					)
					navi.presentViewController(consent, animated: true, completion: nil)
				}
				else {
					chip_warn("must embed eligibility status view controller in a navigation controller")
				}
			}
		}
		
		// apply configurations
		if let config = config {
			check.titleText = config.eligibleLetsCheckMessage ?? check.titleText
			elig.eligibleTitle = config.eligibleTitle ?? elig.eligibleTitle
			elig.eligibleMessage = config.eligibleMessage ?? elig.eligibleMessage
			elig.ineligibleMessage = config.ineligibleMessage ?? elig.ineligibleMessage
		}
		
		// eligibility requirements
		check.waitingForAction = true
		eligibilityRequirements { requirements in
			dispatch_async(dispatch_get_main_queue()) {
				elig.requirements = requirements
				check.waitingForAction = false
			}
		}
		
		check.onActionButtonTap = { controller in
			if let navi = controller.navigationController {
				navi.pushViewController(elig, animated: true)
			}
			else {
				chip_warn("must embed eligibility status view controller in a navigation controller")
			}
		}
		return check
	}
	
	/**
	Resolves the contract's first subject to a Group. This Group is expected to have characteristics that represent eligibility criteria.
	
	- parameter callback: The callback that is called when the group is resolved (or resolution fails); may be on any thread but may be
	called immediately in case of embedded resources.
	*/
	public func eligibilityRequirements(callback: ((requirements: [EligibilityRequirement]?) -> Void)) {
		if let group = contract?.subject?.first {
			group.resolve(Group.self) { group in
				if let characteristics = group?.characteristic {
					var criteria = [EligibilityRequirement]()
					for characteristic in characteristics {
						if let req = characteristic.chip_asEligibilityRequirement() {
							criteria.append(req)
						}
						else {
							chip_warn("this characteristic failed to return an eligibility requirement: \(characteristic.asJSON())")
						}
					}
					callback(requirements: criteria)
				}
				else {
					chip_warn("failed to resolve the contract's subject group or there are no characteristics, hence no eligibility criteria")
					callback(requirements: nil)
				}
			}
		}
		else {
			chip_logIfDebug("the contract does not have a subject, hence no eligibility criteria")
			callback(requirements: nil)
		}
	}
	
	
	// MARK: - Consenting
	
	public func createConsentTask() -> ConsentTask? {
		if let contract = contract {
			let task = ConsentTask(identifier: NSUUID().UUIDString, contract: contract)
			task.prepareWithOptions(options)
			return task
		}
		chip_warn("no Contract, cannot create a consent task")
		return nil
	}
	
	/**
	A consent view controller, preconfigured with the consenting task, that can be presented to have the user go through consent.
	
	You are given two blocks, one of them will be called when the user finishes or exits consenting, never both. They are deallocated after
	either has been called.
	
	- parameter onUserDidConsent: Block executed when the user completes and agrees to consent
	- parameter onUserDidDecline: Block executed when the user cancels or actively declines consent
	*/
	public func consentViewController(onUserDidConsent onConsent: ((controller: ORKTaskViewController) -> Void), onUserDidDecline: ((controller: ORKTaskViewController) -> Void)) -> ORKTaskViewController {
		if nil != onUserDidConsent {
			chip_warn("a `onUserDidConsent` block is already set on \(self), are you already presenting a consent view controller? This might have unintended consequences.")
		}
		onUserDidConsent = onConsent
		onUserDidDeclineConsent = onUserDidDecline
		consentDelegate = ConsentTaskViewControllerDelegate(controller: self)
		
		let consentVC = ORKTaskViewController(task: createConsentTask(), taskRunUUID: NSUUID())
		consentVC.delegate = consentDelegate!
		
		return consentVC
	}
	
	func userDidFinishConsent(taskViewController: ORKTaskViewController, reason: ORKTaskViewControllerFinishReason) {
		var signatureResult: ORKConsentSignatureResult?
		if let results = taskViewController.result.results {
			let sigParent = results.filter() { $0.identifier == "reviewStep" }.first as? ORKStepResult
			signatureResult = sigParent?.results?.filter() { $0 is ORKConsentSignatureResult }.first as? ORKConsentSignatureResult
		}
		
		// if we have a signature in the signature result, we're consented
		if let signatureResult = signatureResult, let signature = signatureResult.signature where nil != signature.signatureImage {
			// TODO: generate PDF
			userDidConsent(taskViewController)
		}
		else if .Completed == reason {
			userDidDeclineConsent(taskViewController)
		}
		else {
			userDidDeclineConsent(taskViewController)		// TODO: room for a new "did-cancel-consent" method
		}
		
		onUserDidConsent = nil
		onUserDidDeclineConsent = nil
		consentDelegate = nil
	}
	
	/**
	Called when the user successfully completes the consent task and agrees to all the things.
	*/
	public func userDidConsent(taskViewController: ORKTaskViewController) {
		if let exec = onUserDidConsent {
			exec(controller: taskViewController)
		}
		NSNotificationCenter.defaultCenter().postNotificationName(C3UserDidConsentNotification, object: self)
	}
	
	/**
	Called when the user aborts consenting or actively declines consent.
	*/
	public func userDidDeclineConsent(taskViewController: ORKTaskViewController) {
		if let exec = onUserDidDeclineConsent {
			exec(controller: taskViewController)
		}
		NSNotificationCenter.defaultCenter().postNotificationName(C3UserDidDeclineConsentNotification, object: self)
	}
	
	
	// MARK: - Consent Signing
	
	/**
	Instantiates a new "Contract" resource and fills the properties to represent a consent signed by a participant referencing the given
	patient.
	*/
	public func signContractWithPatient(patient: Patient, date: NSDate, error: NSErrorPointer) -> Contract? {
		if nil == patient.id {
			patient.id = NSUUID().UUIDString
		}
		if let reference = patient.asRelativeReference() {
			let myContract = contract ?? Contract(json: nil)
			
			// applicable period
			let period = Period(json: nil)
			period.start = date.fhir_asDateTime()
			myContract.applies = period
			
			// the participant/patient is the signer
			let signer = ContractSigner(json: nil)
			signer.type = Coding(json: nil)
			signer.type!.display = "Consent"
			signer.type!.code = "1.2.840.10065.1.12.1.7"
			signer.type!.system = NSURL(string: "http://hl7.org/fhir/vs/contract-signer-type")
			signer.party = reference
			signer.signature = patient.id
			myContract.signer = [signer]
			
			return myContract
		}
		
		if nil != error {
			error.memory = chip_genErrorConsenting("Failed to generate a relative reference for the patient, hence cannot sign this consent")
		}
		chip_warn("failed to generate a relative reference for the patient, hence cannot sign this consent")
		return nil
	}
	
	/**
	Reverse geocodes and de-identifies the patient, then uses the new Patient resource to sign the contract.
	*/
	public func deIdentifyAndSignConsentWithPatient(patient: Patient, date: NSDate, callback: ConsentSigningCallback) {
		deidentifier = DeIdentifier()
		deidentifier!.hipaaCompliantPatient(patient: patient) { patient in
			self.deidentifier = nil
			
			var error: NSError?
			if let contract = self.signContractWithPatient(patient, date: date, error: &error) {
				callback(contract: contract, patient: patient, error: nil)
			}
			else {
				callback(contract: Contract(json: nil), patient: patient, error: error)
			}
		}
	}
	
	
	// MARK: - Consent PDF
	
	/**
	URL to the user-signed contract PDF.
	
	- parameter mustExist: If true will return nil if no file exists at the expected file URL
	*/
	public class func signedConsentPDFURL(mustExist: Bool = false) -> NSURL? {
		if let first = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true).first {
			let url = NSURL(fileURLWithPath: first).URLByAppendingPathComponent("consent-signed.pdf")
			if !mustExist || NSFileManager().fileExistsAtPath(url.path!) {
				return url
			}
		}
		return nil
	}
	
	/**
	*/
	public class func bundledConsentPDFURL() -> NSURL? {
		return NSBundle.mainBundle().URLForResource("consent", withExtension: "pdf")
	}
}


class ConsentTaskViewControllerDelegate: NSObject, ORKTaskViewControllerDelegate {
	
	let controller: ConsentController
	
	init(controller: ConsentController) {
		self.controller = controller
	}
	
	func taskViewController(taskViewController: ORKTaskViewController, didFinishWithReason reason: ORKTaskViewControllerFinishReason, error: NSError?) {
		controller.userDidFinishConsent(taskViewController, reason: reason)
	}
}


/**
	Convenience function to create an NSError in the Consenting error domain.
 */
public func chip_genErrorConsenting(message: String, code: Int = 0) -> NSError {
	return NSError(domain: CHIPConsentingErrorKey, code: code, userInfo: [NSLocalizedDescriptionKey: message])
}

