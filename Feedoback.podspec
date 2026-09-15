# The same sources Swift Package Manager builds, for a project that uses
# CocoaPods instead. Nothing here is a second copy: both read Sources/Feedoback.
#
# SPM cannot resolve a package from a subdirectory of a repository, so the
# release job mirrors this directory to feedoback/feedoback-ios and tags it
# there. A podspec has no such restriction and can point at either.
Pod::Spec.new do |s|
  s.name         = "Feedoback"
  s.version      = "0.1.0"
  s.summary      = "Native feedback for iOS apps."
  s.description  = "A feedback sheet from a control your app already owns, or a floating launcher over it."
  s.homepage     = "https://feedoback.com"
  s.license      = { :type => "MIT", :file => "LICENSE" }
  s.author       = { "Masoud" => "dev3mike@gmail.com" }
  s.platforms    = { :ios => "15.0" }
  s.swift_version = "5.9"

  s.source       = { :git => "https://github.com/feedoback/feedoback-ios.git", :tag => s.version.to_s }
  s.source_files = "Sources/Feedoback/**/*.swift"

  # Required-reason APIs have to be declared or Apple rejects the *host* app.
  # A resource bundle is how a pod ships one.
  s.resource_bundles = { "Feedoback" => ["Sources/Feedoback/PrivacyInfo.xcprivacy"] }

  # Nothing third-party, deliberately: this ships inside someone else's app.
  s.frameworks = "UIKit", "Foundation"
end
