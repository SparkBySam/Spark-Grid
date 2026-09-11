import AppKit
import Foundation

enum LegalLinks {
  static let termsOfUseURL = URL(string: "https://sparksuiteapps.com/legal")!
  static let sparkSuiteURL = URL(string: "https://sparksuiteapps.com")!
  static let tipJarURL = URL(string: "https://buymeacoffee.com/sparkdev")!
  static let feedbackURL = URL(string: "mailto:help@sparksuiteapps.com?subject=Spark%20Grid%20Feedback")!

  static func openTermsOfUse() {
    NSWorkspace.shared.open(termsOfUseURL)
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
