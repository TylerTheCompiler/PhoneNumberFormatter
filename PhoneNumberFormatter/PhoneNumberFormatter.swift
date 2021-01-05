// Copyright (c) 2012, Rick Maddy
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice, this
//   list of conditions and the following disclaimer.
//
// * Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the following disclaimer in the documentation
//   and/or other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
// OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

// Modified by Tyler Prevost on Jan 3, 2021

import UIKit

/// A formatter that can format a string into a country-specific phone number.
public class PhoneNumberFormatter {
    
    /// The shared phone number singleton object.
    public static let shared = PhoneNumberFormatter()
    
    /// Whether the formatter allows for optional phone number prefixes or not when determining if a string is
    /// a valid phone number or not. Default: true.
    public var allowsOptionalPrefixes: Bool
    
    /// Creates a new phone number formatter.
    ///
    /// - Parameters:
    ///   - countryCode: The country code whose locale should be used for formatting phone numbers, or nil to use
    ///                  the current locale. Default: nil.
    ///   - allowsOptionalPrefixes: Whether the formatter allows for optional phone number prefixes or not when
    ///                             determining if a string is a valid phone number or not. Default: true.
    public init(defaultCountry countryCode: String? = nil,
                allowsOptionalPrefixes: Bool = true) {
        guard let dataURL = Bundle.main.url(forResource: "CorePhoneNumbers", withExtension: "ruleset"),
              let data = try? Data(contentsOf: dataURL) else {
            preconditionFailure("The file CorePhoneNumbers.ruleset is not in the main resource bundle. See the README.")
        }
        
        self.data = data
        
        if let countryCode = countryCode, !countryCode.isEmpty {
            defaultCountry = countryCode.lowercased()
        } else {
            defaultCountry = (Locale.current.regionCode ?? "US").lowercased()
        }
        
        self.allowsOptionalPrefixes = allowsOptionalPrefixes
        
        callingCodeOffsets = .init(minimumCapacity: 255)
        callingCodeCountries = .init(minimumCapacity: 255)
        callingCodeData = .init(minimumCapacity: 10)
        countryCallingCode = .init(minimumCapacity: 255)
        
        parseDataHeader()
    }
    
    /// The calling code for the user's default country based on their Region Format setting.
    public var defaultCallingCode: String? {
        callingCode(forCountryCode: defaultCountry)
    }
    
    /// Returns the calling code for the given country code, or nil if no calling code could be found for the
    /// country code.
    ///
    /// `countryCode` must be 2-letter ISO 3166-1 code. Result does not include a leading `+`.
    ///
    /// - Parameter countryCode: The country code of the desired calling code.
    /// - Returns: The calling code for the given country code, or nil if no calling code could be found for the
    ///            country code.
    public func callingCode(forCountryCode countryCode: String) -> String? {
        countryCallingCode[countryCode.lowercased()]
    }
    
    /// Returns the set of country codes for the given calling code.
    ///
    /// `callingCode` should be 1 to 3 digit calling code. Result is a set of matching, lowercase,
    /// 2-letter ISO 3166-1 country codes.
    ///
    /// - Parameter callingCode: The calling code of the desired country codes.
    /// - Returns: The set of country codes for the given calling code.
    public func countryCodes(forCallingCode callingCode: String) -> Set<String> {
        var callingCode = callingCode
        if callingCode.hasPrefix("+") {
            callingCode = String(callingCode.dropFirst())
        }
        
        return callingCodeCountries[callingCode, default: []]
    }
    
    /// Attempts to format a string into a phone number string according to the formatter's country code.
    ///
    /// If the string cannot be formatted into a phone number, the original passed-in string is returned.
    ///
    /// - Parameter phoneNumber: The string to format.
    /// - Returns: A string formatted into a phone number, or the original string if it could not be formatted into
    ///            a phone number.
    public func format(phoneNumber: String) -> String {
        guard !phoneNumber.isEmpty else { return phoneNumber }
        
        // First remove all added punctuation to get just raw phone number characters.
        let str = Self.strip(phoneNumber)
        
        // Phone numbers can be entered by the user in the following formats:
        // 1) +<international prefix><basic number>303
        // 2) <access code><international prefix><basic number>
        // 3) <trunk prefix><basic number>
        // 4) <basic number>
        //
        if str.hasPrefix("+") {
            // Handle case 1. Remove the leading '+'.
            let rest = String(str.dropFirst())
            // Now find the country that matches the number's international prefix
            if let info = findCallingCodeInfo(rest) {
                // We found a matching country. Use that info to format the rest of the number.
                let phone = info.format(rest)
                // Put back the leading '+'.
                return "+\(phone)"
            }
            
            // No match so return original number
            return phoneNumber
        }
        
        // Handles cases 2, 3, and 4.
        // Make sure we have info about the user's current region format.
        guard let storedDefaultCallingCode = storedDefaultCallingCode,
              let info = callingCodeInfo(forCallingCode: storedDefaultCallingCode) else {
            // No match for the user's locale. No formatting possible.
            return phoneNumber
        }
        
        // See if the entered number begins with an access code valid for the user's region format.
        if let accessCode = info.matchingAccessCode(str) {
            // We found a matching access code. This means the rest of the number should be for another country,
            // starting with the other country's international access code.
            // Strip off the access code.
            let rest = String(str.dropFirst(accessCode.count))
            var phone = rest
            // Now see if the rest of the number starts with a known international prefix.
            if let info2 = findCallingCodeInfo(rest) {
                // We found the other country. Format the number for that country.
                phone = info2.format(rest)
            }
            
            if phone.isEmpty {
                // There is just an access code so far.
                return accessCode
            }
            
            // We have an access code and a possibly formatted number. Combine with a space between.
            return "\(accessCode) \(phone)"
        }
        
        // No access code so we handle cases 3 and 4 and format the number using the user's region format.
        return info.format(str)
    }
    
    /// Returns the unformatted version of the given phone number string (only decimal digits, `+`, `*`, and `#`).
    ///
    /// - Parameter phoneNumber: The phone number to unformat.
    /// - Returns: An unformatted phone number.
    public func unformat(phoneNumber: String) -> String {
        Self.strip(phoneNumber)
    }
    
    /// Determines if the given phone number is a complete phone number (with or without formatting).
    ///
    /// - Parameters:
    ///   - phoneNumber: The phone number string to check.
    /// - Returns: Whether the phone number string is a valid phone number string or not.
    public func isPhoneNumberValid(phoneNumber: String) -> Bool {
        guard !phoneNumber.isEmpty else { return false }
        
        // First remove all added punctuation to get just raw phone number characters.
        let str = Self.strip(phoneNumber)
        
        // Phone numbers can be entered by the user in the following formats:
        // 1) +<international prefix><basic number>303
        // 2) <access code><international prefix><basic number>
        // 3) <trunk prefix><basic number>
        // 4) <basic number>
        //
        if str.hasPrefix("+") {
            // Handle case 1. Remove the leading '+'.
            let rest = String(str.dropFirst())
            // Now find the country that matches the number's international prefix
            if let info = findCallingCodeInfo(rest) {
                // We found a matching country. Use that info to see if the number is complete.
                return info.isValidPhoneNumber(rest, allowsOptionalPrefixes: allowsOptionalPrefixes)
            }
            
            // No matching country code
            return false
        }
        
        // Handles cases 2, 3, and 4.
        // Make sure we have info about the user's current region format.
        guard let storedDefaultCallingCode = storedDefaultCallingCode,
              let info = callingCodeInfo(forCallingCode: storedDefaultCallingCode) else {
            // No match for the user's locale. No formatting possible.
            return false
        }
        
        // See if the entered number begins with an access code valid for the user's region format.
        if let accessCode = info.matchingAccessCode(str) {
            // We found a matching access code. This means the rest of the number should be for another country,
            // starting with the other country's international access code.
            // Strip off the access code.
            let rest = String(str.dropFirst(accessCode.count))
            if !rest.isEmpty {
                // Now see if the rest of the number starts with a known international prefix.
                if let info2 = findCallingCodeInfo(rest) {
                    // We found a matching country. Use that info to see if the number is complete.
                    return info2.isValidPhoneNumber(rest, allowsOptionalPrefixes: allowsOptionalPrefixes)
                }
                
                // No matching country code
                return false
            }
            
            // There is just an access code so far.
            return false
        }
        
        // No access code so we handle cases 3 and 4 and validate the number using the user's region format.
        return info.isValidPhoneNumber(str, allowsOptionalPrefixes: allowsOptionalPrefixes)
    }
    
    /// Formats a text field's text as a phone number if possible.
    ///
    /// Use this in your `UITextFieldDelegate`'s `textField(_:shouldChangeCharactersIn:replacementString:)` method to
    /// dynamically format your text field's text as the user types out a phone number. The boolean value that this
    /// method returns should be the value you return from that method, too.
    ///
    /// - Parameters:
    ///   - textField: The text field that is attempting to change its selected text.
    ///   - string: The replacement string that the text field wants to replace the selected text with.
    ///   - validPhoneNumberHandler: A closure called when the text field's text is determined to be a valid phone
    ///                              number or not. The boolean value returned is whether the text field's text is a
    ///                              valid phone number or not. Use this to update your UI to reflect the change in
    ///                              phone number validity. For example, you can change the `textColor` of the
    ///                              text field to `UIColor.red` when the boolean is false (meaning an invalid phone
    ///                              number), and `UIColor.label` when it is true (meaning a valid phone number).
    ///                              Default: nil.
    /// - Returns: Whether the text field should change the characters in the given range or not.
    public func formatText(of textField: UITextField,
                           replacementString string: String,
                           validPhoneNumberHandler: ((_ isValid: Bool) -> Void)? = nil) -> Bool {
        // For some reason, the 'range' parameter isn't always correct when backspacing through a phone number
        // This calculates the proper range from the text field's selection range.
        guard let selRange = textField.selectedTextRange else { return true }
        let selStartPos = selRange.start
        let selEndPos = selRange.end
        let start = textField.offset(from: textField.beginningOfDocument, to: selStartPos)
        let end = textField.offset(from: textField.beginningOfDocument, to: selEndPos)
        let repRange: NSRange
        if start == end {
            if string.isEmpty {
                repRange = NSMakeRange(start - 1, 1)
            } else {
                repRange = NSMakeRange(start, end - start)
            }
        } else {
            repRange = NSMakeRange(start, end - start)
        }
        
        // This is what the new text will be after adding/deleting 'string'
        let txt = textField.text!.replacingCharacters(in: Range(repRange, in: textField.text!)!,
                                                            with: string)
        
        // This is the newly formatted version of the phone number
        let phone = format(phoneNumber: txt)
        
        if let validPhoneNumberHandler = validPhoneNumberHandler {
            validPhoneNumberHandler(isPhoneNumberValid(phoneNumber: phone))
        }
        
        // If these are the same then just let the normal text changing take place
        if phone == txt {
            return true
        }
        
        // The two are different which means the adding/removal of a character had a bigger effect
        // from adding/removing phone number formatting based on the new number of characters in the text field
        // The trick now is to ensure the cursor stays after the same character despite the change in formatting.
        // So first let's count the number of non-formatting characters up to the cursor in the unchanged text.
        var cnt = 0
        for i in 0..<(repRange.location + string.count) {
            if Self.phoneChars.contains(txt[txt.index(txt.startIndex, offsetBy: i)].unicodeScalars.first!) {
                cnt += 1
            }
        }
        
        // Now let's find the position, in the newly formatted string, of the same number of non-formatting characters.
        var pos = phone.count
        var cnt2 = 0
        for i in 0..<phone.count {
            if Self.phoneChars.contains(phone[phone.index(phone.startIndex, offsetBy: i)].unicodeScalars.first!) {
                cnt2 += 1
            }
            
            if cnt2 == cnt {
                pos = i + 1
                break
            }
        }
        
        // Replace the text with the updated formatting
        textField.text = phone
        
        // Make sure the caret is in the right place
        if let startPos = textField.position(from: textField.beginningOfDocument, offset: pos) {
            let textRange = textField.textRange(from: startPos, to: startPos)
            textField.selectedTextRange = textRange
        }
        
        return false
    }
    
    #if DEBUG
    /// Prints the phone number formatter to standard output.
    public func dump() {
        let callingCodes = callingCodeOffsets.keys.sorted()
        for callingCode in callingCodes {
            let info = callingCodeInfo(forCallingCode: callingCode)
            print("Info for calling code \(callingCode):", info ?? "nil")
        }
        
        print("flagRules:", Self.flagRules)
        print("extra1 calling codes:", Self.extra1CallingCodes)
        print("extra2 calling codes:", Self.extra2CallingCodes)
        print("extra3 calling codes:", Self.extra3CallingCodes)
    }
    #endif
    
    // MARK: - Private
    
    private static func strip(_ str: String) -> String {
        str.filter { phoneChars.contains($0.unicodeScalars.first!) }
    }
    
    private func value32(offset: UInt32) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        var res: UInt32 = 0
        res += UInt32(data[Int(offset) + 0]) << 0
        res += UInt32(data[Int(offset) + 1]) << 8
        res += UInt32(data[Int(offset) + 2]) << 16
        res += UInt32(data[Int(offset) + 3]) << 24
        return res
    }
    
    private func value16(offset: UInt32) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        var res: UInt16 = 0
        res += UInt16(data[Int(offset) + 0]) << 0
        res += UInt16(data[Int(offset) + 1]) << 8
        return res
    }
    
    @discardableResult
    private func callingCodeInfo(forCallingCode callingCode: String) -> CallingCodeInfo? {
        if let res = callingCodeData[callingCode] { return res }
        guard let num = callingCodeOffsets[callingCode] else { return nil }
        
        return data.withUnsafeBytes { bytes in
            let start = num
            var offset = start
            let res = CallingCodeInfo()
            res.callingCode = callingCode
            res.countries = callingCodeCountries[callingCode, default: []]
            callingCodeData[callingCode] = res
            
            let block1Len = value16(offset: offset)
            offset += 2
            #if DEBUG
            let extra1 = value16(offset: offset)
            #endif
            offset += 2
            let block2Len = value16(offset: offset)
            offset += 2
            #if DEBUG
            let extra2 = value16(offset: offset)
            #endif
            offset += 2
            let setCnt = value16(offset: offset)
            offset += 2
            #if DEBUG
            let extra3 = value16(offset: offset)
            #endif
            offset += 2
            
            #if DEBUG
            if extra1 != 0 { Self.extra1CallingCodes[extra1, default: []].append(res) }
            if extra2 != 0 { Self.extra2CallingCodes[extra2, default: []].append(res) }
            if extra3 != 0 { Self.extra3CallingCodes[extra3, default: []].append(res) }
            #endif
            
            var strs = [String]()
            var optionalStr = String(cString: (bytes.baseAddress! + Int(offset)).assumingMemoryBound(to: CChar.self),
                                     encoding: .utf8)
            while let str = optionalStr, !str.isEmpty {
                strs.append(str)
                offset += UInt32(str.count + 1)
                optionalStr = String(cString: (bytes.baseAddress! + Int(offset)).assumingMemoryBound(to: CChar.self),
                                     encoding: .utf8)
            }
            res.trunkPrefixes = strs
            offset += 1 // skip NULL
            
            strs = []
            optionalStr = String(cString: (bytes.baseAddress! + Int(offset)).assumingMemoryBound(to: CChar.self),
                                 encoding: .utf8)
            while let str = optionalStr, !str.isEmpty {
                strs.append(str)
                offset += UInt32(str.count + 1)
                optionalStr = String(cString: (bytes.baseAddress! + Int(offset)).assumingMemoryBound(to: CChar.self),
                                     encoding: .utf8)
            }
            res.intlPrefixes = strs
            
            var ruleSets = [RuleSet]()
            offset = start + UInt32(block1Len) // Start of rule sets
            for _ in 0..<setCnt {
                let ruleSet = RuleSet()
                let matchCnt = value16(offset: offset)
                ruleSet.matchLen = Int(matchCnt)
                offset += 2
                let ruleCnt = value16(offset: offset)
                offset += 2
                var rules = [PhoneRule]()
                for _ in 0..<ruleCnt {
                    let rule = PhoneRule()
                    rule.minVal = Int(value32(offset: offset))
                    offset += 4
                    rule.maxVal = Int(value32(offset: offset))
                    offset += 4
                    rule.byte8 = Int(bytes[Int(offset)])
                    offset += 1
                    rule.maxLen = Int(bytes[Int(offset)])
                    offset += 1
                    rule.otherFlag = Int(bytes[Int(offset)])
                    offset += 1
                    rule.prefixLen = Int(bytes[Int(offset)])
                    offset += 1
                    rule.flag12 = Int(bytes[Int(offset)])
                    offset += 1
                    rule.flag13 = Int(bytes[Int(offset)])
                    offset += 1
                    let strOffset = value16(offset: offset)
                    offset += 2
                    let fmtOffset = Int(UInt32(start) + UInt32(block1Len) + UInt32(block2Len) + UInt32(strOffset))
                    rule.format = String(cString: (bytes.baseAddress! + fmtOffset).assumingMemoryBound(to: CChar.self),
                                         encoding: .utf8) ?? ""
                    
                    // Several formats contain [[9]] or [[8]]. Using the Contacts app as a test, I can find no use
                    // for these. Do they mean "optional"? They don't seem to have any use. This code strips out
                    // anything in [[..]]
                    if let openPos = rule.format.range(of: "[["),
                       let closePos = rule.format.range(of: "]]") {
                        rule.format = "\(rule.format[..<openPos.lowerBound])\(rule.format[closePos.upperBound...])"
                    }
                    
                    rules.append(rule)
                    
                    if rule.hasIntlPrefix {
                        ruleSet.hasRuleWithIntlPrefix = true
                    }
                    
                    if rule.hasTrunkPrefix {
                        ruleSet.hasRuleWithTrunkPrefix = true
                    }
                    
                    #if DEBUG
                    rule.countries = res.countries
                    rule.callingCode = res.callingCode
                    rule.matchLen = Int(matchCnt)
                    
                    if rule.byte8 != 0 {
                        var data = Self.flagRules["byte8", default: [:]]
                        var list = data[rule.byte8, default: []]
                        list.append(rule)
                        data[rule.byte8] = list
                        Self.flagRules["byte8"] = data
                    }
                    
                    if rule.prefixLen != 0 {
                        var data = Self.flagRules["prefixLen", default: [:]]
                        var list = data[rule.prefixLen, default: []]
                        list.append(rule)
                        data[rule.prefixLen] = list
                        Self.flagRules["prefixLen"] = data
                    }
                    
                    if rule.otherFlag != 0 {
                        var data = Self.flagRules["otherFlag", default: [:]]
                        var list = data[rule.otherFlag, default: []]
                        list.append(rule)
                        data[rule.otherFlag] = list
                        Self.flagRules["otherFlag"] = data
                    }
                    
                    if rule.flag12 != 0 {
                        var data = Self.flagRules["flag12", default: [:]]
                        var list = data[rule.flag12, default: []]
                        list.append(rule)
                        data[rule.flag12] = list
                        Self.flagRules["flag12"] = data
                    }
                    
                    if rule.flag13 != 0 {
                        var data = Self.flagRules["flag13", default: [:]]
                        var list = data[rule.flag13, default: []]
                        list.append(rule)
                        data[rule.flag13] = list
                        Self.flagRules["flag13"] = data
                    }
                    #endif
                }
                
                ruleSet.rules = rules
                ruleSets.append(ruleSet)
            }
            
            res.ruleSets = ruleSets
            
            return res
        }
    }
    
    private func parseDataHeader() {
        let count = value32(offset: 0)
        let base: UInt32 = count * 12 + 4
        data.withUnsafeBytes { bytes in
            var spot: UInt32 = 4
            for _ in 0..<count {
                let callingCode = String(cString: (bytes.baseAddress! + Int(spot)).assumingMemoryBound(to: CChar.self),
                                         encoding: .utf8)
                spot += 4
                let country = String(cString: (bytes.baseAddress! + Int(spot)).assumingMemoryBound(to: CChar.self),
                                     encoding: .utf8)
                spot += 4
                let offset = value32(offset: spot) + base
                spot += 4
                
                if country == defaultCountry {
                    storedDefaultCallingCode = callingCode
                }
                
                if let country = country {
                    countryCallingCode[country] = callingCode
                    
                    if let callingCode = callingCode {
                        callingCodeOffsets[callingCode] = offset
                        var countries = callingCodeCountries[callingCode, default: []]
                        countries.insert(country)
                        callingCodeCountries[callingCode] = countries
                    }
                }
            }
        }
        
        if let storedDefaultCallingCode = storedDefaultCallingCode {
            callingCodeInfo(forCallingCode: storedDefaultCallingCode)
        }
    }
    
    private func findCallingCodeInfo(_ str: String) -> CallingCodeInfo? {
        for i in 0..<3 {
            if i < str.count {
                let callingCode = String(str[..<str.index(str.startIndex, offsetBy: i + 1)])
                if let res = callingCodeInfo(forCallingCode: callingCode) {
                    return res
                }
            } else {
                return nil
            }
        }
        
        return nil
    }
    
    private static let phoneChars = CharacterSet(charactersIn: "0123456789+*#")
    #if DEBUG
    private static var extra1CallingCodes: [UInt16: [CallingCodeInfo]] = [:]
    private static var extra2CallingCodes: [UInt16: [CallingCodeInfo]] = [:]
    private static var extra3CallingCodes: [UInt16: [CallingCodeInfo]] = [:]
    private static var flagRules: [String: [Int: [PhoneRule]]] = [:]
    #endif
    
    private let data: Data
    private let defaultCountry: String
    private var storedDefaultCallingCode: String?
    private var callingCodeOffsets: [String: UInt32]
    private var callingCodeCountries: [String: Set<String>]
    private var callingCodeData: [String: CallingCodeInfo]
    private var countryCallingCode: [String: String]
}
 
private class PhoneRule: CustomStringConvertible {
    var minVal: Int = 0
    var maxVal: Int = 0
    var byte8: Int = 0
    var maxLen: Int = 0
    var otherFlag: Int = 0
    var prefixLen: Int = 0
    var flag12: Int = 0
    var flag13: Int = 0
    var format: String = ""
    
    var hasIntlPrefix: Bool {
        (flag12 & 0x02) != 0
    }
    
    var hasTrunkPrefix: Bool {
        (flag12 & 0x01) != 0
    }
    
    #if DEBUG
    var countries: Set<String> = []
    var callingCode: String = ""
    var matchLen: Int = 0
    #endif
    
    func format(_ str: String, intlPrefix: String?, trunkPrefix: String?) -> String {
        var hadC = false
        var hadN = false
        var hasOpen = false
        var spot = 0
        var res = ""
        for (index, ch) in format.enumerated() {
            switch ch {
            case "c":
                // Add international prefix if there is one.
                hadC = true
                if let intlPrefix = intlPrefix {
                    res += intlPrefix
                }
                
            case "n":
                // Add trunk prefix if there is one.
                hadN = true
                if let trunkPrefix = trunkPrefix {
                    res += trunkPrefix
                }
                
            case "#":
                // Add next digit from number. If there aren't enough digits left then do nothing unless we need to
                // space-fill a pair of parenthesis.
                if spot < str.count {
                    res += String(str.dropFirst(spot).first!)
                    spot += 1
                } else if hasOpen {
                    res += " "
                }
                
            case "(":
                // Flag we found an open paren so it can be space-filled. But only do so if we aren't beyond the
                // end of the number.
                if spot < str.count {
                    hasOpen = true
                }
                
                fallthrough // fall through
            
            default: // rest like ) and -
                var previousChar: Character {
                    format[format.index(format.startIndex, offsetBy: index - 1)]
                }
                
                // Don't show space after n if no trunkPrefix or after c if no intlPrefix
                if !(ch == " " && index > 0 && ((previousChar == "n" && trunkPrefix == nil) ||
                                                (previousChar == "c" && intlPrefix == nil))) {
                    // Only show punctuation if not beyond the end of the supplied number.
                    // The only exception is to show a close paren if we had found
                    if spot < str.count || (hasOpen && ch == ")") {
                        res += String(ch)
                        if ch == ")" {
                            hasOpen = false // close it
                        }
                    }
                }
            }
        }
        
        // Not all format strings have a 'c' or 'n' in them. If we have an international prefix or a trunk prefix
        // but the format string doesn't explictly say where to put it then simply add it to the beginning.
        if let intlPrefix = intlPrefix, !hadC {
            res.insert(contentsOf: "\(intlPrefix) ", at: res.startIndex)
        } else if let trunkPrefix = trunkPrefix, !hadN {
            res.insert(contentsOf: trunkPrefix, at: res.startIndex)
        }
        
        return res
    }
    
    var description: String {
        #if DEBUG
        return """
        PhoneRule: {
            countries: \(countries)
            callingCode: \(callingCode)
            matchlen: \(matchLen)
            minVal: \(minVal)
            maxVal: \(maxVal)
            byte8: \(byte8)
            maxLen: \(maxLen)
            nFlag: \(otherFlag)
            prefixLen: \(prefixLen)
            flag12: \(flag12)
            flag13: \(flag13)
            format: \(format)
        }
        """
        #else
        return """
        PhoneRule: {
            minVal: \(minVal)
            maxVal: \(maxVal)
            byte8: \(byte8)
            maxLen: \(maxLen)
            nFlag: \(otherFlag)
            prefixLen: \(prefixLen)
            flag12: \(flag12)
            flag13: \(flag13)
            format: \(format)
        }
        """
        #endif
    }
}

private class RuleSet: CustomStringConvertible {
    var matchLen: Int = 0
    var rules: [PhoneRule] = []
    var hasRuleWithIntlPrefix = false
    var hasRuleWithTrunkPrefix = false
    
    func format(_ str: String,
                intlPrefix: String?,
                trunkPrefix: String?,
                prefixRequired: Bool) -> String? {
        // First check the number's length against this rule set's match length. If the supplied number is too short
        // then this rule set is ignored.
        guard str.count >= matchLen else {
            return nil // not long enough to compare
        }
        
        // Otherwise we make two passes through the rules in the set. The first pass looks for rules that match the
        // number's prefix and length. It also finds the best rule match based on the prefix flag.
        let begin = str[..<str.index(str.startIndex, offsetBy: matchLen)]
        let val = Int(begin) ?? 0
        
        // Check the rule's range and length against the start of the number
        for rule in rules where val >= rule.minVal && val <= rule.maxVal && str.count <= rule.maxLen {
            if prefixRequired {
                // This pass is trying to find the most restrictive match.
                // A prefix flag of 0 means the format string does not explicitly use the trunk prefix or
                // international prefix. So only use one of these if the number has no trunk or international prefix.
                // A prefix flag of 1 means the format string has a reference to the trunk prefix. Only use that
                // rule if the number has a trunk prefix.
                // A prefix flag of 2 means the format string has a reference to the international prefix.
                // Only use that rule if the number has an international prefix.
                if ((rule.flag12 & 0x03) == 0 && trunkPrefix == nil && intlPrefix == nil) ||
                    (trunkPrefix != nil && rule.hasTrunkPrefix) ||
                    (intlPrefix != nil && rule.hasIntlPrefix) {
                    return rule.format(str, intlPrefix: intlPrefix, trunkPrefix: trunkPrefix)
                }
            } else {
                // This pass is less restrictive. If this is called it means there was not an exact match based on
                // prefix flag and any supplied prefix in the number. So now we can use this rule if there is no
                // prefix regardless of the flag12.
                if (trunkPrefix == nil && intlPrefix == nil) ||
                    (trunkPrefix != nil && rule.hasTrunkPrefix) ||
                    (intlPrefix != nil && rule.hasIntlPrefix) {
                    return rule.format(str, intlPrefix: intlPrefix, trunkPrefix: trunkPrefix)
                }
            }
        }
        
        // If we get this far it means the supplied number has either a trunk prefix or an international prefix but
        // none of the rules explictly use that prefix. So now we make one last pass finding a matching rule by totally
        // ignoring the prefix flag.
        if !prefixRequired {
            if let intlPrefix = intlPrefix {
                // Strings with intl prefix should use rule with c in it if possible. If not found above then find
                // matching rule with no c.
                return rules.first {
                    val >= $0.minVal && val <= $0.maxVal && str.count <= $0.maxLen &&
                        (trunkPrefix == nil || $0.hasTrunkPrefix)
                }?.format(str, intlPrefix: intlPrefix, trunkPrefix: trunkPrefix)
            } else if let trunkPrefix = trunkPrefix {
                // Strings with trunk prefix should use rule with n in it if possible. If not found above then find
                // matching rule with no n.
                return rules.first {
                    val >= $0.minVal && val <= $0.maxVal && str.count <= $0.maxLen &&
                        (intlPrefix == nil || $0.hasIntlPrefix)
                }?.format(str, intlPrefix: intlPrefix, trunkPrefix: trunkPrefix)
            }
        }
        
        return nil // no match found
    }
    
    func isValid(_ str: String,
                 intlPrefix: String?,
                 trunkPrefix: String?,
                 prefixRequired: Bool) -> Bool {
        // First check the number's length against this rule set's match length. If the supplied number is the wrong
        // length then this rule set is ignored.
        guard str.count >= matchLen else {
            return false // not the correct length
        }
        
        // Otherwise we make two passes through the rules in the set. The first pass looks for rules that match the
        // number's prefix and length. It also finds the best rule match based on the prefix flag.
        let begin = str[..<str.index(str.startIndex, offsetBy: matchLen)]
        let val = Int(begin) ?? 0
        
        // Check the rule's range and length against the start of the number
        for rule in rules where val >= rule.minVal && val <= rule.maxVal && str.count == rule.maxLen {
            if prefixRequired {
                // This pass is trying to find the most restrictive match.
                // A prefix flag of 0 means the format string does not explicitly use the trunk prefix or
                // international prefix. So only use one of these if the number has no trunk or international prefix.
                // A prefix flag of 1 means the format string has a reference to the trunk prefix. Only use that
                // rule if the number has a trunk prefix.
                // A prefix flag of 2 means the format string has a reference to the international prefix.
                // Only use that rule if the number has an international prefix.
                if ((rule.flag12 & 0x03) == 0 && trunkPrefix == nil && intlPrefix == nil) ||
                    (trunkPrefix != nil && rule.hasTrunkPrefix) ||
                    (intlPrefix != nil && rule.hasIntlPrefix) {
                    return true // full match
                }
            } else {
                // This pass is less restrictive. If this is called it means there was not an exact match based on
                // prefix flag and any supplied prefix in the number. So now we can use this rule if there is no
                // prefix regardless of the flag12.
                if (trunkPrefix == nil && intlPrefix == nil) ||
                    (trunkPrefix != nil && rule.hasTrunkPrefix) ||
                    (intlPrefix != nil && rule.hasIntlPrefix) {
                    return true // full match
                }
            }
        }
        
        // If we get this far it means the supplied number has either a trunk prefix or an international prefix but
        // none of the rules explictly use that prefix. So now we make one last pass finding a matching rule by totally
        // ignoring the prefix flag.
        if !prefixRequired {
            if intlPrefix != nil, !hasRuleWithIntlPrefix {
                // Strings with intl prefix should use rule with c in it if possible. If not found above then find
                // matching rule with no c.
                return rules.contains {
                    val >= $0.minVal && val <= $0.maxVal && str.count == $0.maxLen &&
                        (trunkPrefix == nil || $0.hasTrunkPrefix)
                }
            } else if trunkPrefix != nil, !hasRuleWithTrunkPrefix {
                // Strings with trunk prefix should use rule with n in it if possible. If not found above then find
                // matching rule with no n.
                return rules.contains {
                    val >= $0.minVal && val <= $0.maxVal && str.count == $0.maxLen &&
                        (intlPrefix == nil || $0.hasIntlPrefix)
                }
            }
        }
        
        return false // no match found
    }
    
    var description: String {
        """
        RuleSet: {
            matchLen: \(matchLen)
            rules: \(rules)
        }
        """
    }
}

private class CallingCodeInfo: CustomStringConvertible {
    var countries: Set<String> = []
    var callingCode = ""
    var trunkPrefixes: [String] = []
    var intlPrefixes: [String] = []
    var ruleSets: [RuleSet] = []
    var formatStrings: [String] = []
    
    func matchingAccessCode(_ str: String) -> String? {
        intlPrefixes.first { str.hasPrefix($0) }
    }
    
    func matchingTrunkCode( _ str: String) -> String? {
        trunkPrefixes.first { str.hasPrefix($0) }
    }
    
    func format(_ orig: String) -> String {
        // First see if the number starts with either the country's trunk prefix or international prefix.
        // If so save it off and remove from the number.
        var str = orig
        var trunkPrefix: String?
        var intlPrefix: String?
        if str.hasPrefix(callingCode) {
            intlPrefix = callingCode
            str = String(str.dropFirst(callingCode.count))
        } else if let trunk = matchingTrunkCode(str) {
            trunkPrefix = trunk
            str = String(str.dropFirst(trunk.count))
        }
        
        // Scan through all sets find best match with no optional prefixes allowed
        for set in ruleSets {
            if let phone = set.format(str, intlPrefix: intlPrefix, trunkPrefix: trunkPrefix, prefixRequired: true) {
                return phone
            }
        }
        
        // No exact matches so now allow for optional prefixes
        for set in ruleSets {
            if let phone = set.format(str, intlPrefix: intlPrefix, trunkPrefix: trunkPrefix, prefixRequired: false) {
                return phone
            }
        }
        
        // No rules matched. If there is an international prefix then display it and the
        // rest of the number with a space.
        if let intlPrefix = intlPrefix, !str.isEmpty {
            return "\(intlPrefix) \(str)"
        }
        
        // Nothing worked so just return the original number as-is.
        return orig
    }
    
    func isValidPhoneNumber(_ orig: String, allowsOptionalPrefixes: Bool) -> Bool {
        // First see if the number starts with either the country's trunk prefix or international prefix.
        // If so save it off and remove from the number.
        var str = orig
        var trunkPrefix: String?
        var intlPrefix: String?
        if str.hasPrefix(callingCode) {
            intlPrefix = callingCode
            str = String(str.dropFirst(callingCode.count))
        } else if let trunk = matchingTrunkCode(str) {
            trunkPrefix = trunk
            str = String(str.dropFirst(trunk.count))
        }
        
        // Scan through all sets find best match with no optional prefixes allowed
        for set in ruleSets where set.isValid(str, intlPrefix: intlPrefix,
                                              trunkPrefix: trunkPrefix,
                                              prefixRequired: true) {
            return true
        }
        
        guard allowsOptionalPrefixes else { return false }
        
        // No exact matches so now allow for optional prefixes
        for set in ruleSets where set.isValid(str, intlPrefix: intlPrefix,
                                              trunkPrefix: trunkPrefix,
                                              prefixRequired: false) {
            return true
        }
        
        // The number isn't complete
        return false
    }
    
    var description: String {
        return """
        CallingCodeInfo {
            countries: \(countries)
            code: \(callingCode)
            trunkPrefixes: \(trunkPrefixes)
            intlPrefixes: \(intlPrefixes)
            rule sets: \(ruleSets)
        }
        """
    }
}
