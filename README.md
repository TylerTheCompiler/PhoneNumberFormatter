# PhoneNumberFormatter (forked from RMPhoneFormat)

(This is a Swift-based version of [RMPhoneFormat](https://github.com/rmaddy/RMPhoneFormat), an awesome phone number formatting class made by Rick Maddy many years ago.)

PhoneNumberFormatter provides a simple to use class for formatting and validating phone numbers in iOS apps. The formatting should replicate what you would see in the Contacts app for the same phone number.

The included sample project demonstrates how to use the formatting class to setup a text field that formats itself as the user types in a phone number. While the sample app is for iOS, the PhoneNumberFormatter class should work as-is under macOS.

## Setup

This class depends on a copy of an Apple-provided private framework file named CorePhoneNumbers.ruleset being copied into the app's resource bundle.

The CorePhoneNumbers.ruleset file is found at:

    /System/Library/PrivateFrameworks/CorePhoneNumbers.framework/Versions/A/Resources/CorePhoneNumbers.ruleset

Add PhoneNumberFormatter.swift to your own project, as well as the above CorePhoneNumbers.ruleset file (or use a Build Phase run script to automatically copy it from the above address to your project, like the example project does).

## Usage

In its simplest form you do the following:

    let formatter = PhoneNumberFormatter()
    // Call any number of times
    let numberString = // the phone number to format
    let formattedNumber = formatter.format(phoneNumber: numberString)

You can also pass in a specific default country code if you don't want to rely on the Region Format setting. Pass in a valid ISO 3166-1 two-letter country code:

    let formatter = PhoneNumberFormatter(defaultCountry: "UK")
    // Call any number of times
    let numberString = // the phone number to format
    let formattedNumber = formatter.format(phoneNumber: numberString)

You may also use the singleton interface if desired:

    let formatter = PhoneNumberFormatter.shared
    // Call any number of times
    let numberString = // the phone number to format
    let formattedNumber = formatter.format(phoneNumber: numberString)

To validate a phone number you can do the following:

    let formatter = PhoneNumberFormatter()
    // Call any number of times
    let numberString = // the phone number to validate
    let isValid = formatter.isPhoneNumberValid(phoneNumber: numberString)
    
The phone number to validate can include formatting characters or not. The number will be valid if there are an appropriate set of digits.

PhoneNumberFormatter can also be used to look up a country's calling code:

    let formatter = PhoneNumberFormatter.shared
    let callingCode = formatter.callingCode(forCountryCode: "AU") // Australia - returns 61
    let defaultCallingCode = formatter.defaultCallingCode // based on current Region Format (locale)

PhoneNumberFormatter can also be used to format a `UITextField` as the user is typing into it. To do this, in your text field delegate's `textField(_:shouldChangeCharactersIn:replacementString:)` method, return that value returned from your phone number formatter's `formatText(of:replacementString:validPhoneNumberHandler:)` method, passing in your text field and the replacement string given to you by the delegate method:

    func textField(_ textField: UITextField,
                   shouldChangeCharactersIn range: NSRange,
                   replacementString string: String) -> Bool {
        return yourPhoneNumberFormatter.formatText(of: textField, replacementString: string) { isValidPhoneNumber in
            textField.textColor = isValidPhoneNumber ? .label : .red
        }
    }

The optional closure passed into `validPhoneNumberHandler` of the above method may be used to update your UI to reflect whether the phone number is valid or not as the user is typing it. In the above example, the text field's text color becomes red if the phone number is not valid, and becomes the normal text color otherwise.

## Notes

See the comments in PhoneNumberFormatter.swift for additional details.

Please note that the format of the CorePhoneNumbers.ruleset file is undocumented. There are aspects to this file that are not yet understood. This means that some phone numbers in some countries may not be formatted correctly.

## Issues

If you encounter an issue where a phone number is formatted differently with PhoneNumberFormatter than the Contacts app, then create an [issue](https://github.com/TylerTheCompiler/PhoneNumberFormatter/issues). Be sure to provide the phone number, the output from PhoneNumberFormatter, the output shown in Contacts, and the Region Format setting from the Settings app.

## License
    Copyright (c) 2012, Rick Maddy
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice, this
      list of conditions and the following disclaimer.

    * Redistributions in binary form must reproduce the above copyright notice,
      this list of conditions and the following disclaimer in the documentation
      and/or other materials provided with the distribution.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
    ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
    WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
    DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
    FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
    DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
    OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
    OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
    OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
