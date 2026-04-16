Pod::Spec.new do |s|
  s.name             = 'Valhalla'
  s.version          = '0.0.1'
  s.summary          = 'Valhalla offline routing engine (vendored xcframework)'
  s.description      = 'Vendored Valhalla XCFramework built by scripts/build_valhalla_ios.sh'
  s.homepage         = 'https://github.com/valhalla/valhalla'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Valhalla' => 'valhalla' }

  # This is a local pod; source is the folder itself.
  s.source           = { :path => '.' }

  s.platform         = :ios, '17.0'
  s.vendored_frameworks = 'Valhalla.xcframework'

  # Ensure consuming targets compile as C++20 when including Valhalla headers.
  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++20',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'GCC_ENABLE_CPP_EXCEPTIONS' => 'YES',
    'GCC_ENABLE_CPP_RTTI' => 'YES',
    'HEADER_SEARCH_PATHS' => [
      '$(SRCROOT)/../third_party/valhalla',
      '$(SRCROOT)/../third_party/valhalla/third_party/rapidjson/include',
      '$(SRCROOT)/../third_party/valhalla/third_party/date/include',
      '$(SRCROOT)/../third_party/valhalla/third_party/unordered_dense/include',
      '$(SRCROOT)/../android/app/src/main/cpp/include',
      '$(SRCROOT)/../third_party/valhalla/third_party/protozero/include',
      '$(SRCROOT)/../third_party/valhalla/third_party/vtzero/include',
      '$(SRCROOT)/../third_party/vcpkg/installed/arm64-ios/include'
    ].join(' ')
  }
  s.user_target_xcconfig = {
    'HEADER_SEARCH_PATHS' => [
      '$(SRCROOT)/../third_party/valhalla',
      '$(SRCROOT)/../third_party/valhalla/third_party/rapidjson/include',
      '$(SRCROOT)/../third_party/valhalla/third_party/date/include',
      '$(SRCROOT)/../third_party/valhalla/third_party/unordered_dense/include',
      '$(SRCROOT)/../android/app/src/main/cpp/include',
      '$(SRCROOT)/../third_party/valhalla/third_party/protozero/include',
      '$(SRCROOT)/../third_party/valhalla/third_party/vtzero/include',
      '$(SRCROOT)/../third_party/vcpkg/installed/arm64-ios/include'
    ].join(' ')
  }
end

