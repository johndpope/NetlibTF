//******************************************************************************
//  Created by Edward Connell on 4/12/16
//  Copyright © 2016 Connell Research. All rights reserved.
//
import Foundation
import Dispatch

//==============================================================================
/// LogInfo
/// this is used to manage which log to use and message parameters
public struct LogInfo {
    /// the log to write to
    var log: Log
    /// the reporting level of the object, which allows different objects
    /// to have different reporting levels to fine tune output
    var logLevel: LogLevel = .error
    /// `namePath` is used when reporting from hierarchical structures
    /// such as a model, so that duplicate names such as `weights` are
    /// put into context
    var namePath: String
    /// the nesting level within a hierarchical model to aid in
    /// message formatting.
    var nestingLevel: Int
    /// a helper to create logging info for a child object in a hierarchy
    public func child(_ name: String) -> LogInfo {
        return LogInfo(log: log,
                       logLevel: .error,
                       namePath: "\(namePath)/\(name)",
                       nestingLevel: nestingLevel + 1)
    }
}

//==============================================================================
// _Logging
public protocol _Logging {
    var log: Log { get }
    var logLevel: LogLevel { get }
    var logNamePath: String { get }
    var logNestingLevel: Int { get }
    /// reports whether a message at the specified level will be logged
    /// - Parameter level: the level to test
    func willLog(level: LogLevel) -> Bool
    /// writes a message to the log
    ///
    func writeLog(_ message: @autoclosure () -> String,
                  level: LogLevel,
                  indent: Int, trailing: String,
                  minCount: Int)
    ///
    func diagnostic(_ message: @autoclosure () -> String,
                    categories: LogCategories,
                    indent: Int, trailing: String,
                    minCount: Int)
}

public extension _Logging {
    //--------------------------------------------------------------------------
    // willLog
    func willLog(level: LogLevel) -> Bool {
        return level <= log.level || level <= logLevel
    }
    
    //--------------------------------------------------------------------------
    /// writeLog
    ///
    func writeLog(_ message: @autoclosure () -> String,
                  level: LogLevel = .error,
                  indent: Int = 0, trailing: String = "",
                  minCount: Int = 80) {
        guard level <= log.level || level <= logLevel else { return }
        log.write(level: level,
                  message: message(),
                  nestingLevel: indent + logNestingLevel,
                  trailing: trailing, minCount: minCount)
    }
    
    //--------------------------------------------------------------------------
    // diagnostic
    func diagnostic(_ message: @autoclosure () -> String,
                    categories: LogCategories,
                    indent: Int = 0, trailing: String = "",
                    minCount: Int = 80) {
        guard log.level >= .diagnostic || logLevel >= .diagnostic else { return}
        // if subcategories have been selected on the log object
        // then make sure the caller's category is desired
        if let mask = log.categories?.rawValue,
            categories.rawValue & mask == 0 { return }
        
        log.write(level: .diagnostic,
                  message: message(),
                  nestingLevel: indent + logNestingLevel,
                  trailing: trailing, minCount: minCount)
    }
}


//==============================================================================
// Logging
public protocol Logging : _Logging { }

public extension Logging {
    var log: Log { return _ThreadLocalStream.value.currentLogInfo.log }
    var logLevel: LogLevel { return _ThreadLocalStream.value.currentLogInfo.logLevel }
    var logNamePath: String { return _ThreadLocalStream.value.currentLogInfo.namePath }
    var logNestingLevel: Int { return _ThreadLocalStream.value.currentLogInfo.nestingLevel }
}

//==============================================================================
// Logger
public protocol Logger : _Logging {
    var logInfo: LogInfo { get }
}

extension Logger {
    public var log: Log { return logInfo.log }
    public var logLevel: LogLevel { return logInfo.logLevel }
    public var logNamePath: String { return logInfo.namePath }
    public var logNestingLevel: Int { return logInfo.nestingLevel }
}

//==============================================================================
// Log
final public class Log: ObjectTracking {
	// properties
	public var categories: LogCategories?
    public var history = [LogEvent]()
    public var level: LogLevel = .error
	public var maxHistory = 0
	public var silent = false
	public var tabSize = 2
	public var url: URL?

    // ObjectTracking
    public private(set) var trackingId: Int = 0

    // A log can be written to freely by any thread,
    // so create write queue
	private let queue = DispatchQueue(label: "Log.queue")
	private static let levelColWidth =
		String(describing: LogLevel.diagnostic).count

	//--------------------------------------------------------------------------
	/// write
    /// writes an entry into the log
    /// - Parameter level: the level of the message
    /// - Parameter message:
    /// - Parameter nestingLevel:
    /// - Parameter trailing:
    /// - Parameter minCount:
	public func write(level: LogLevel,
                      message: @autoclosure () -> String,
                      nestingLevel: Int = 0,
	                  trailing: String = "",
                      minCount: Int = 0) {
        // protect against mt writes
		queue.sync { [unowned self] in
            // record in history
            let messageStr = message()
			if maxHistory > 0 {
				if self.history.count == self.maxHistory {
                    self.history.removeFirst()
                }
				self.history.append(LogEvent(level: level,
                                             nestingLevel: nestingLevel,
				                             message: messageStr))
			}

            // create fixed width string for level column
			let levelStr = String(describing: level).padding(
				toLength: Log.levelColWidth, withPad: " ", startingAt: 0)

			let indent = String(repeating: " ",
                                count: nestingLevel * self.tabSize)
			var eventStr = levelStr + ": " + indent + messageStr

			// add trailing fill if desired
			if !trailing.isEmpty {
				let fillCount = minCount - eventStr.count
				if messageStr.isEmpty {
					eventStr += String(repeating: trailing, count: fillCount)
				} else {
					if fillCount > 1 {
						eventStr += " " + String(repeating: trailing,
                                                 count: fillCount - 1)
					}
				}
			}

			// TODO: add write to log file support
			//		if let uri = uri {
			//
			//		}

			// write to the console
			if !self.silent && self.url == nil && self.maxHistory == 0 {
				print(eventStr)
			}
		}
	}
}

//==============================================================================
// LogEvent
public struct LogEvent {
	var level: LogLevel
	var nestingLevel: Int
	var message: String
}

//------------------------------------------------------------------------------
// LogColors
//  http://stackoverflow.com/questions/5947742/how-to-change-the-output-color-of-echo-in-linux
public enum LogColor: String {
	case reset       = "\u{1b}[m"
	case red         = "\u{1b}[31m"
	case green       = "\u{1b}[32m"
	case yellow      = "\u{1b}[33m"
	case blue        = "\u{1b}[34m"
	case magenta     = "\u{1b}[35m"
	case cyan        = "\u{1b}[36m"
	case white       = "\u{1b}[37m"
	case bold        = "\u{1b}[1m"
	case boldRed     = "\u{1b}[1;31m"
	case boldGreen   = "\u{1b}[1;32m"
	case boldYellow  = "\u{1b}[1;33m"
	case boldBlue    = "\u{1b}[1;34m"
	case boldMagenta = "\u{1b}[1;35m"
	case boldCyan    = "\u{1b}[1;36m"
	case boldWhite   = "\u{1b}[1;37m"
}

public func setText(_ text: String, color: LogColor) -> String {
	#if os(Linux)
	return color.rawValue + text + LogColor.reset.rawValue
	#else
	return text
	#endif
}

//------------------------------------------------------------------------------
// LogCategories
public struct LogCategories: OptionSet {
    public init(rawValue: Int) { self.rawValue = rawValue }
	public let rawValue: Int
	public static let dataAlloc    = LogCategories(rawValue: 1 << 0)
	public static let dataCopy     = LogCategories(rawValue: 1 << 1)
	public static let dataMutation = LogCategories(rawValue: 1 << 2)
    public static let initialize   = LogCategories(rawValue: 1 << 3)
	public static let streamAlloc  = LogCategories(rawValue: 1 << 4)
	public static let streamSync   = LogCategories(rawValue: 1 << 5)
}

// strings
let allocString    = "[\(setText("ALLOC  ", color: .cyan))]"
let createString   = "[\(setText("CREATE ", color: .cyan))]"
let copyString     = "[\(setText("COPY   ", color: .blue))]"
let releaseString  = "[\(setText("RELEASE", color: .cyan))]"
let blockString    = "[\(setText("BLOCK  ", color: .red))]"
let waitString     = "[\(setText("WAIT   ", color: .yellow))]"
let syncString     = "[\(setText("SYNC   ", color: .yellow))]"
let recordString   = "[\(setText("RECORD ", color: .yellow))]"
let mutationString = "[\(setText("MUTATE ", color: .blue))]"

//------------------------------------------------------------------------------
// LogLevel
public enum LogLevel: Int, Comparable {
	case error, warning, status, diagnostic

	public init?(string: String) {
		switch string {
		case "error"     : self = .error
		case "warning"   : self = .warning
		case "status"    : self = .status
		case "diagnostic": self = .diagnostic
		default: return nil
		}
	}
}

public func<(lhs: LogLevel, rhs: LogLevel) -> Bool {
	return lhs.rawValue < rhs.rawValue
}
