//
//  QuestionnaireQuestionPromise.swift
//  C3PRO
//
//  Created by Pascal Pfiffner on 4/20/15.
//  Copyright (c) 2015 Boston Children's Hospital. All rights reserved.
//

import Foundation
import SMART
import ResearchKit


let kORKTextChoiceSystemSeparator: Character = " "
let kORKTextChoiceDefaultSystem = "https://fhir.smalthealthit.org"
let kORKTextChoiceMissingCodeCode = "⚠️"


/**
	A promise that can fulfill a questionnaire question into an ORKQuestionStep.
 */
class QuestionnaireQuestionPromise: QuestionnairePromiseProto
{
	/// The promises' question.
	let question: QuestionnaireGroupQuestion
	
	/// The step(s), internally assigned after the promise has been successfully fulfilled.
	internal(set) var steps: [ORKStep]?
	
	init(question: QuestionnaireGroupQuestion) {
		self.question = question
	}
	
	
	// MARK: - Fulfilling
	
	/** Fulfill the promise.
		
	    Once the promise has been successfully fulfilled, the `step` property will be assigned. No guarantees as to on
	    which queue the callback will be called.

	    :param: callback The callback to be called when done; note that even when you get an error, some steps might
	        have successfully been allocated still, so don't throw everything away just because you receive errors
	 */
	func fulfill(parentRequirements: [ResultRequirement]?, callback: ((errors: [NSError]?) -> Void)) {
		let linkId = question.linkId ?? NSUUID().UUIDString
		let (title, text) = question.chip_bestTitleAndText()
		
		// resolve answer format, THEN resolve sub-groups, if any
		question.chip_asAnswerFormat() { format, berror in
			var steps = [ORKStep]()
			var errors = [NSError]()
			var requirements = parentRequirements ?? [ResultRequirement]()
			
			if let fmt = format {
				let step = ConditionalQuestionStep(identifier: linkId, title: title, answer: fmt)
				step.fhirType = self.question.type
				step.text = text
				step.optional = !(self.question.required ?? false)
				
				// questions "enableWhen" requirements
				var error: NSError?
				if let myreqs = self.question.chip_enableQuestionnaireElementWhen(&error) {
					requirements.extend(myreqs)
				}
				else if nil != error {
					errors.append(error!)
				}
				
				if !requirements.isEmpty {
					step.addRequirements(requirements: requirements)
				}
				steps.append(step)
			}
			else {
				errors.append(berror ?? chip_genErrorQuestionnaire("Failed to map question type to ResearchKit answer format"))
			}
			
			// do we have sub-groups?
			if let subgroups = self.question.group {
				let gpromises = subgroups.map() { QuestionnaireGroupPromise(group: $0) }
				
				// fulfill all group promises
				let queueGroup = dispatch_group_create()
				for gpromise in gpromises {
					dispatch_group_enter(queueGroup)
					gpromise.fulfill(requirements) { berrors in
						if nil != berrors {
							errors.extend(berrors!)
						}
						dispatch_group_leave(queueGroup)
					}
				}
				
				// all done
				dispatch_group_notify(queueGroup, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)) {
					let gsteps = gpromises.filter() { return nil != $0.steps }.flatMap() { return $0.steps! }
					steps.extend(gsteps)
					
					self.steps = steps
					callback(errors: count(errors) > 0 ? errors : nil)
				}
			}
			else {
				self.steps = steps
				callback(errors: errors)
			}
		}
	}
	
	
	// MARK: - Printable
	
	var description: String {
		return NSString(format: "<QuestionnaireQuestionPromise %p>", unsafeAddressOf(self)) as String
	}
}


// MARK: -


extension QuestionnaireGroupQuestion
{
	func chip_bestTitleAndText() -> (String?, String?) {
		let cDisplay = concept?.filter() { return nil != $0.display }.map() { return $0.display! }
		let cCodes = concept?.filter() { return nil != $0.code }.map() { return $0.code! }
		
		var ttl = cDisplay?.first ?? cCodes?.first
		var txt = text
		
		if nil == ttl {
			ttl = text
			txt = nil
		}
		if nil == txt {
			txt = chip_questionInstruction() ?? chip_questionHelpText()		// even if the title is still nil, we won't want to populate the title with help text
		}
		
		return (ttl?.chip_stripMultipleSpaces(), txt?.chip_stripMultipleSpaces())
	}
	
	func chip_questionMinOccurs() -> Int? {
		return extensionsFor("http://hl7.org/fhir/StructureDefinition/questionnaire-minOccurs")?.first?.valueInteger
	}
	
	func chip_questionMaxOccurs() -> Int? {
		return extensionsFor("http://hl7.org/fhir/StructureDefinition/questionnaire-maxOccurs")?.first?.valueInteger
	}
	
	func chip_questionInstruction() -> String? {
		return extensionsFor("http://hl7.org/fhir/StructureDefinition/questionnaire-instruction")?.first?.valueString
	}
	
	func chip_questionHelpText() -> String? {
		return extensionsFor("http://hl7.org/fhir/StructureDefinition/questionnaire-help")?.first?.valueString
	}
	
	func chip_numericAnswerUnit() -> String? {
		return extensionsFor("http://hl7.org/fhir/StructureDefinition/questionnaire-units")?.first?.valueString
	}
	
	func chip_defaultAnswer() -> Extension? {
		return extensionsFor("http://hl7.org/fhir/StructureDefinition/questionnaire-defaultValue")?.first
	}
	
	
	/**
	Determine ResearchKit's answer format for the question type.
	
	Questions are multiple choice if "repeats" is set to true and the "max-occurs" extension is either not defined or larger than 1. See
	`chip_answerChoiceStyle`.
	
	TODO: "open-choice" allows to choose an option OR to give a textual response: implement
	
	[x] ORKScaleAnswerFormat:           "integer" plus min- and max-values defined, where max > min
	[ ] ORKContinuousScaleAnswerFormat:
	[ ] ORKValuePickerAnswerFormat:
	[ ] ORKImageChoiceAnswerFormat:
	[x] ORKTextAnswerFormat:            "string", "url"
	[x] ORKTextChoiceAnswerFormat:      "choice", "choice-open" (!)
	[x] ORKBooleanAnswerFormat:         "boolean"
	[x] ORKNumericAnswerFormat:         "decimal", "integer", "quantity"
	[x] ORKDateAnswerFormat:            "date", "dateTime", "instant"
	[x] ORKTimeOfDayAnswerFormat:       "time"
	[ ] ORKTimeIntervalAnswerFormat:
	*/
	func chip_asAnswerFormat(callback: ((format: ORKAnswerFormat?, error: NSError?) -> Void)) {
		let link = linkId ?? "<nil>"
		if let type = type {
			switch type {
			case "boolean":		callback(format: ORKAnswerFormat.booleanAnswerFormat(), error: nil)
			case "decimal":		callback(format: ORKAnswerFormat.decimalAnswerFormatWithUnit(nil), error: nil)
			case "integer":
				let minVals = chip_minValue()
				let maxVals = chip_maxValue()
				let minVal = minVals?.filter() { return $0.valueInteger != nil }.first?.valueInteger
				let maxVal = maxVals?.filter() { return $0.valueInteger != nil }.first?.valueInteger
				if let minVal = minVal, maxVal = maxVal where maxVal > minVal {
					let minDesc = minVals?.filter() { return $0.valueString != nil }.first?.valueString
					let maxDesc = maxVals?.filter() { return $0.valueString != nil }.first?.valueString
					let defVal = chip_defaultAnswer()?.valueInteger ?? minVal
					let format = ORKAnswerFormat.scaleAnswerFormatWithMaximumValue(maxVal, minimumValue: minVal, defaultValue: defVal,
						step: 1, vertical: (maxVal - minVal > 5),
						maximumValueDescription: maxDesc, minimumValueDescription: minDesc)
					callback(format: format, error: nil)
					
				}
				else {
					callback(format: ORKAnswerFormat.integerAnswerFormatWithUnit(nil), error: nil)
				}
			case "quantity":	callback(format: ORKAnswerFormat.decimalAnswerFormatWithUnit(chip_numericAnswerUnit()), error: nil)
			case "date":		callback(format: ORKAnswerFormat.dateAnswerFormat(), error: nil)
			case "dateTime":	callback(format: ORKAnswerFormat.dateTimeAnswerFormat(), error: nil)
			case "instant":		callback(format: ORKAnswerFormat.dateTimeAnswerFormat(), error: nil)
			case "time":		callback(format: ORKAnswerFormat.timeOfDayAnswerFormat(), error: nil)
			case "string":		callback(format: ORKAnswerFormat.textAnswerFormat(), error: nil)
			case "url":			callback(format: ORKAnswerFormat.textAnswerFormat(), error: nil)
			case "choice":
				chip_resolveAnswerChoices() { choices, error in
					if nil != error || nil == choices {
						callback(format: nil, error: error ?? chip_genErrorQuestionnaire("There are no choices in question «\(self.text)» [linkId: \(link)]"))
					}
					else {
						callback(format: ORKAnswerFormat.choiceAnswerFormatWithStyle(self.chip_answerChoiceStyle(), textChoices: choices!), error: nil)
					}
				}
			case "open-choice":
				chip_resolveAnswerChoices() { choices, error in
					if nil != error || nil == choices {
						callback(format: nil, error: error ?? chip_genErrorQuestionnaire("There are no choices in question «\(self.text)» [linkId: \(link)]"))
					}
					else {
						callback(format: ORKAnswerFormat.choiceAnswerFormatWithStyle(self.chip_answerChoiceStyle(), textChoices: choices!), error: nil)
					}
				}
				//case "attachment":	callback(format: nil, error: nil)
				//case "reference":		callback(format: nil, error: nil)
			default:
				callback(format: nil, error: chip_genErrorQuestionnaire("Cannot map question type \"\(type)\" to ResearchKit answer format [linkId: \(link)]"))
			}
		}
		else {
			NSLog("Question «\(text)» does not have an answer type, assuming text answer [linkId: \(link)]")
			callback(format: ORKAnswerFormat.textAnswerFormat(), error: nil)
		}
	}
	
	/**
	For `choice` type questions, retrieves the possible answers and returns them as ORKTextChoice in the callback.
	
	The `value` property of the text choice is a combination of the coding system URL and the code, separated by a space. If no system URL
	is provided, "https://fhir.smalthealthit.org" is used.
	*/
	func chip_resolveAnswerChoices(callback: ((choices: [ORKTextChoice]?, error: NSError?) -> Void)) {
		options?.resolve(ValueSet.self) { valueSet in
			var choices = [ORKTextChoice]()
			
			// we have an expanded ValueSet
			if let expansion = valueSet?.expansion?.contains {
				for option in expansion {
					let system = option.system?.absoluteString ?? kORKTextChoiceDefaultSystem
					let code = option.code ?? kORKTextChoiceMissingCodeCode
					let value = "\(system)\(kORKTextChoiceSystemSeparator)\(code)"
					let text = ORKTextChoice(text: option.display ?? code, value: value)
					choices.append(text)
				}
			}
			
			// valueset defines its own concepts
			else if let options = valueSet?.define?.concept {
				let system = valueSet?.define?.system?.absoluteString ?? kORKTextChoiceDefaultSystem
				for option in options {
					let code = option.code ?? kORKTextChoiceMissingCodeCode			// code is a required property, so SHOULD always be present
					let value = "\(system)\(kORKTextChoiceSystemSeparator)\(code)"
					let text = ORKTextChoice(text: option.display ?? code, value: value)
					choices.append(text)
				}
			}
			
			// valueset includes codes
			else if let options = valueSet?.compose?.include {		// TODO: also support `import`
				for option in options {
					let system = option.system?.absoluteString ?? kORKTextChoiceDefaultSystem	// system is a required property
					if let concepts = option.concept {
						for concept in concepts {
							let code = concept.code ?? kORKTextChoiceMissingCodeCode	// code is a required property, so SHOULD always be present
							let value = "\(system)\(kORKTextChoiceSystemSeparator)\(code)"
							let text = ORKTextChoice(text: concept.display ?? code, value: value)
							choices.append(text)
						}
					}
				}
			}
			
			// all done
			if count(choices) > 0 {
				callback(choices: choices, error: nil)
			}
			else {
				callback(choices: nil, error: chip_genErrorQuestionnaire("Question «\(self.text)» does not specify choices in its ValueSet"))
			}
		}
	}
	
	/**
	For `choice` type questions, inspect if the given question is single or multiple choice. Questions are multiple choice if "repeats" is
	true and the "max-occurs" extension is either not defined or larger than 1.
	*/
	func chip_answerChoiceStyle() -> ORKChoiceAnswerStyle {
		let multiple = repeats ?? ((chip_questionMaxOccurs() ?? 1) > 1)
		let style: ORKChoiceAnswerStyle = multiple ? .MultipleChoice : .SingleChoice
		return style
	}
}

