//
//  PhoneNumberKit.swift
//  PhoneNumberKit
//
//  Created by Roy Marmelstein on 03/10/2015.
//  Copyright © 2015 Roy Marmelstein. All rights reserved.
//

import Foundation
#if os(iOS)
import CoreTelephony
#endif

public typealias MetadataCallback = (() throws -> Data?)

public final class PhoneNumberKit: NSObject {

    // Manager objects
    let metadataManager: MetadataManager
    let parseManager: ParseManager
    let regexManager = RegexManager()

    // MARK: Lifecycle
    public init(metadataCallback: @escaping MetadataCallback = PhoneNumberKit.defaultMetadataCallback) {
       self.metadataManager = MetadataManager(metadataCallback: metadataCallback)
       self.parseManager = ParseManager(metadataManager: metadataManager, regexManager: regexManager)
   }

    // MARK: Parsing

    /// Parses a number string, used to create PhoneNumber objects. Throws.
    ///
    /// - Parameters:
    ///   - numberString: the raw number string.
    ///   - region: ISO 639 compliant region code.
    ///   - ignoreType: Avoids number type checking for faster performance.
    /// - Returns: PhoneNumber object.
    public func parse(_ numberString: String, withRegion region: String = PhoneNumberKit.defaultRegionCode(), ignoreType: Bool = false) throws -> PhoneNumber {

        var numberStringWithPlus = numberString

        do {
            return try parseManager.parse(numberString, withRegion: region, ignoreType: ignoreType)
        } catch {
            if (numberStringWithPlus.first != "+") {
                numberStringWithPlus = "+" + numberStringWithPlus
            }
        }

        return try parseManager.parse(numberStringWithPlus, withRegion: region, ignoreType: ignoreType)
    }

    /// Parses an array of number strings. Optimised for performance. Invalid numbers are ignored in the resulting array
    ///
    /// - parameter numberStrings:               array of raw number strings.
    /// - parameter region:                      ISO 639 compliant region code.
    /// - parameter ignoreType:   Avoids number type checking for faster performance.
    ///
    /// - returns: array of PhoneNumber objects.
    public func parse(_ numberStrings: [String], withRegion region: String = PhoneNumberKit.defaultRegionCode(), ignoreType: Bool = false, shouldReturnFailedEmptyNumbers: Bool = false) -> [PhoneNumber] {
        return parseManager.parseMultiple(numberStrings, withRegion: region, ignoreType: ignoreType, shouldReturnFailedEmptyNumbers: shouldReturnFailedEmptyNumbers)
    }

    // MARK: Formatting

    /// Formats a PhoneNumber object for dispaly.
    ///
    /// - parameter phoneNumber: PhoneNumber object.
    /// - parameter formatType:  PhoneNumberFormat enum.
    /// - parameter prefix:      whether or not to include the prefix.
    ///
    /// - returns: Formatted representation of the PhoneNumber.
    public func format(_ phoneNumber: PhoneNumber, toType formatType: PhoneNumberFormat, withPrefix prefix: Bool = true) -> String {
        if formatType == .e164 {
            let formattedNationalNumber = phoneNumber.adjustedNationalNumber()
            if prefix == false {
                return formattedNationalNumber
            }
            return "+\(phoneNumber.countryCode)\(formattedNationalNumber)"
        } else {
            let formatter = Formatter(phoneNumberKit: self)
            let regionMetadata = metadataManager.mainTerritoryByCode[phoneNumber.countryCode]
            let formattedNationalNumber = formatter.format(phoneNumber: phoneNumber, formatType: formatType, regionMetadata: regionMetadata)
            if formatType == .international && prefix == true {
                return "+\(phoneNumber.countryCode) \(formattedNationalNumber)"
            } else {
                return formattedNationalNumber
            }
        }
    }

    // MARK: Country and region code

    /// Get a list of all the countries in the metadata database
    ///
    /// - returns: An array of ISO 639 compliant region codes.
    public func allCountries() -> [String] {
        let results = metadataManager.territories.map {$0.codeID}
        return results
    }

    /// Get an array of ISO 639 compliant region codes corresponding to a given country code.
    ///
    /// - parameter countryCode: international country code (e.g 44 for the UK).
    ///
    /// - returns: optional array of ISO 639 compliant region codes.
    public func countries(withCode countryCode: UInt64) -> [String]? {
        let results = metadataManager.filterTerritories(byCode: countryCode)?.map {$0.codeID}
        return results
    }

    /// Get an main ISO 639 compliant region code for a given country code.
    ///
    /// - parameter countryCode: international country code (e.g 1 for the US).
    ///
    /// - returns: ISO 639 compliant region code string.
    public func mainCountry(forCode countryCode: UInt64) -> String? {
        let country = metadataManager.mainTerritory(forCode: countryCode)
        return country?.codeID
    }

    /// Get an international country code for an ISO 639 compliant region code
    ///
    /// - parameter country: ISO 639 compliant region code.
    ///
    /// - returns: international country code (e.g. 33 for France).
    public func countryCode(for country: String) -> UInt64? {
        let results = metadataManager.filterTerritories(byCountry: country)?.countryCode
        return results
    }

    /// Get leading digits for an ISO 639 compliant region code.
    ///
    /// - parameter country: ISO 639 compliant region code.
    ///
    /// - returns: leading digits (e.g. 876 for Jamaica).
    public func leadingDigits(for country: String) -> String? {
        let leadingDigits = metadataManager.filterTerritories(byCountry: country)?.leadingDigits
        return leadingDigits
    }

    /// Determine the region code of a given phone number.
    ///
    /// - parameter phoneNumber: PhoneNumber object
    ///
    /// - returns: Region code, eg "US", or nil if the region cannot be determined.
    public func getRegionCode(of phoneNumber: PhoneNumber) -> String? {
        return parseManager.getRegionCode(of: phoneNumber.nationalNumber, countryCode: phoneNumber.countryCode, leadingZero: phoneNumber.leadingZero)
    }

    /// Get an array of possible phone number lengths for the country, as specified by the parameters.
    ///
    /// - parameter country: ISO 639 compliant region code.
    /// - parameter phoneNumberType: PhoneNumberType enum.
    /// - parameter lengthType: PossibleLengthType enum.
    ///
    /// - returns: Array of possible lengths for the country. May be empty.
    public func possiblePhoneNumberLengths(forCountry country: String, phoneNumberType: PhoneNumberType, lengthType: PossibleLengthType) -> [Int] {
        guard let territory = metadataManager.filterTerritories(byCountry: country) else { return [] }

        let possibleLengthsList: [MetadataPossibleLengths] = possiblePhoneNumberLengths(forTerritory: territory, phoneNumberType: phoneNumberType)

        // reduce array into single comma-separated string of length values
        let nationalLengthsAsString: String = possibleLengthsList.compactMap { $0.national }.reduce("") { $0 + ",\($1)"}
        let localOnlyLengthsAsString: String = possibleLengthsList.compactMap { $0.localOnly }.reduce("") { $0 + ",\($1)"}

        switch lengthType {
        case .national:
            let stringValues = nationalLengthsAsString.components(separatedBy: ",")
            return stringValues.compactMap { Int($0) }
        case .localOnly:
            let stringValues = localOnlyLengthsAsString.components(separatedBy: ",")
            return stringValues.compactMap { Int($0) }
        }
    }

    private func possiblePhoneNumberLengths(forTerritory territory: MetadataTerritory, phoneNumberType: PhoneNumberType) -> [MetadataPossibleLengths] {
        var lengths: MetadataPossibleLengths?

        switch phoneNumberType {
        case .fixedLine:        lengths = territory.fixedLine?.possibleLengths
        case .mobile:           lengths = territory.mobile?.possibleLengths
        case .fixedOrMobile:
            let fixedLengths = possiblePhoneNumberLengths(forTerritory: territory, phoneNumberType: .fixedLine)
            let mobileLengths = possiblePhoneNumberLengths(forTerritory: territory, phoneNumberType: .mobile)
            return fixedLengths + mobileLengths

        case .pager:            lengths = territory.pager?.possibleLengths
        case .personalNumber:   lengths = territory.personalNumber?.possibleLengths
        case .premiumRate:      lengths = territory.premiumRate?.possibleLengths
        case .sharedCost:       lengths = territory.sharedCost?.possibleLengths
        case .tollFree:         lengths = territory.tollFree?.possibleLengths
        case .voicemail:        lengths = territory.voicemail?.possibleLengths
        case .voip:             lengths = territory.voip?.possibleLengths
        case .uan:              lengths = territory.uan?.possibleLengths
        case .unknown:          lengths = nil
        case .notParsed:        lengths = nil
        }

        guard let possibleLengths = lengths else { return [] }
        return [possibleLengths]
    }

    public func exampleNumber(forCountry country: String, phoneNumberType: PhoneNumberType) -> String? {
        guard let territory = metadataManager.filterTerritories(byCountry: country) else { return nil }

        switch phoneNumberType {
        case .fixedLine:        return territory.fixedLine?.exampleNumber
        case .mobile:           return territory.mobile?.exampleNumber
        case .fixedOrMobile:    return territory.mobile?.exampleNumber
        case .pager:            return territory.pager?.exampleNumber
        case .personalNumber:   return territory.personalNumber?.exampleNumber
        case .premiumRate:      return territory.premiumRate?.exampleNumber
        case .sharedCost:       return territory.sharedCost?.exampleNumber
        case .tollFree:         return territory.tollFree?.exampleNumber
        case .voicemail:        return territory.voicemail?.exampleNumber
        case .voip:             return territory.voip?.exampleNumber
        case .uan:              return territory.uan?.exampleNumber
        case .unknown:          return nil
        case .notParsed:        return nil
        }
    }

  public func nationalPrefixTransformRule(forCountry country: String) -> String? {
    return metadataManager.filterTerritories(byCountry: country)?.nationalPrefixTransformRule
  }

    // MARK: Class functions

    /// Get a user's default region code
    ///
    /// - returns: A computed value for the user's current region - based on the iPhone's carrier and if not available, the device region.
    public class func defaultRegionCode() -> String {
#if os(iOS)
        let networkInfo = CTTelephonyNetworkInfo()
        let carrier = networkInfo.subscriberCellularProvider
        if let isoCountryCode = carrier?.isoCountryCode {
            return isoCountryCode.uppercased()
        }
#endif
        let currentLocale = Locale.current
        if #available(iOS 10.0, *), let countryCode = currentLocale.regionCode {
            return countryCode.uppercased()
        } else {
			if let countryCode = (currentLocale as NSLocale).object(forKey: .countryCode) as? String {
                return countryCode.uppercased()
            }
        }
        return PhoneNumberConstants.defaultCountry
    }

    /// Default metadta callback, reads metadata from PhoneNumberMetadata.json file in bundle
    ///
    /// - returns: an optional Data representation of the metadata.
    public static func defaultMetadataCallback() throws -> Data? {
        let frameworkBundle = Bundle(for: PhoneNumberKit.self)
        guard let jsonPath = frameworkBundle.path(forResource: "PhoneNumberMetadata", ofType: "json") else {
            throw PhoneNumberError.metadataNotFound
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
        return data
    }

}
