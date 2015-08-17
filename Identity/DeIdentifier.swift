//
//  DeIdentifier.swift
//  ResearchCHIP
//
//  Created by Pascal Pfiffner on 7/20/15.
//  Copyright (c) 2015 Boston Children's Hospital. All rights reserved.
//

import Foundation
import SMART


/**
	Class to help in de-identifying patient data according to HIPAA's Safe Harbor guidelines.
 */
public class DeIdentifier
{
	var geocoder: Geocoder?
	
	public init() {  }
	
	
	// MARK: - Patient Details
	
	/**
	Takes the given Patient resource and creates a new instance with only HIPAA compliant de-identified data.
	
	:param patient: The Patient resource to de-identify
	:param callback: The callback to call when de-identification has completed
	*/
	public func hipaaCompliantPatient(patient inPatient: Patient, callback: ((patient: Patient) -> Void)) {
		geocoder = Geocoder()
		geocoder!.hipaaCompliantCurrentLocation { address, error in
			self.geocoder = nil
			
			let patient = Patient(json: nil)
			patient.id = inPatient.id
			if let address = address {
				patient.address = [address]
			}
			patient.gender = inPatient.gender
			if let bday = inPatient.birthDate {
				patient.birthDate = self.hipaaCompliantBirthDate(bday)
			}
			callback(patient: patient)
		}
	}
	
	/**
	Returns a Date that is compliant to HIPAA's Safe Harbor guidelines: year only and capped at 90 years of age.
	
	:returns: A compliant Date instance
	*/
	public func hipaaCompliantBirthDate(birthdate: Date) -> Date {
		let current = NSDate().fhir_asDate()
		let year = (current.year - birthdate.year) > 90 ? (current.year - 90) : current.year
		return Date(year: year, month: nil, day: nil)
	}
}