//
//  RobloxURLHandler.swift
//  RoStrap
//
//  Created by iivusly on 6/10/23.
//

class RobloxURLHandler {
	static var separator = "+"
	static var nameSeparator = ":"
	
	var urlString: String
	var parsedArguments: [String:String] = [:]
	
	init(_ input: String) {
		urlString = input
	}
	
	enum parsingError: Error {
		case cannotFindName, cannotFindValue
	}
	
	func parse() throws {
		try urlString.components(separatedBy: RobloxURLHandler.separator).forEach { component in
			let split = component.components(separatedBy: RobloxURLHandler.nameSeparator)
			
			guard let name = split.first else {
				throw parsingError.cannotFindName
			}
			
			guard let value = split.last else {
				throw parsingError.cannotFindValue
			}
			
			parsedArguments[name] = value
		}
	}
	
	func formatForRobloxPlayer() -> [String] {
		var arguments: [String] = []
		
		parsedArguments.forEach { (key: String, value: String) in
			switch key {
			case "LaunchExp":
				arguments.append(contentsOf: ["-launchExp", value])
			case "gameinfo":
				arguments.append(contentsOf: ["-ticket", value])
			case "placelauncherurl":
				arguments.append(contentsOf: ["-scriptURL", value.removingPercentEncoding!])
			case "robloxLocale":
				arguments.append(contentsOf: ["-rloc", value])
			case "gameLocale":
				arguments.append(contentsOf: ["-gloc", value])
			case "launchtime":
				arguments.append(contentsOf: ["-launchtime", value])
			case "browsertrackerid":
				arguments.append(contentsOf: ["-browserTrackerId", value])
			default:
				let _: String? = nil
			}
		}
		
		return arguments
	}
}
