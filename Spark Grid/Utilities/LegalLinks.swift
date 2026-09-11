import AppKit
import Foundation

enum LegalLinks {
  static let termsOfUseURL = URL(string: "https://sparkgridapp.com/legal")!
  static let privacyURL = URL(string: "https://sparkgridapp.com/privacy")!
  static let supportURL = URL(string: "https://sparkgridapp.com/support")!
  static let sparkSuiteURL = URL(string: "https://sparksuiteapps.com")!
  static let tipJarURL = URL(string: "https://buymeacoffee.com/sparkdev")!
  static let feedbackURL = URL(string: "mailto:help@sparkgridapp.com?subject=Spark%20Grid%20Support")!

  static func openTermsOfUse() {
    NSWorkspace.shared.open(termsOfUseURL)
  }

  static func openPrivacy() {
    NSWorkspace.shared.open(privacyURL)
  }

  static func openSupport() {
    NSWorkspace.shared.open(supportURL)
  }

  static func openSparkSuite() {
    NSWorkspace.shared.open(sparkSuiteURL)
  }

  static func openTipJar() {
    NSWorkspace.shared.open(tipJarURL)
  }

  static func openFeedback() {
    NSWorkspace.shared.open(feedbackURL)
  }
}

enum AppUINotifications {
  static let showAbout = Notification.Name("com.sparkbysam.SparkGrid.showAbout")
}
