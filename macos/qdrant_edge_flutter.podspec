#
# macOS side of the qdrant_edge_flutter FFI plugin.
#
# Same approach as iOS: vendor the Rust static library and reference its symbols
# from Classes/qdrant_edge_flutter_keepalive.c so the linker keeps them. Dart
# resolves them at runtime via DynamicLibrary.process().
#
# Build the .a with scripts/build-macos.sh before `pod install`.
#
Pod::Spec.new do |s|
  s.name             = 'qdrant_edge_flutter'
  s.version          = '0.1.0'
  s.summary          = 'On-device vector search for Flutter (qdrant-edge + BM25).'
  s.description      = 'On-device vector search powered by the qdrant-edge Rust crate with built-in BM25 embedding.'
  s.homepage         = 'https://github.com/hkulekci/flutter-qdrant-edge'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = { 'Haydar Külekci' => 'haydar@motivolog.com' }
  s.source           = { :path => '.' }
  s.platform         = :osx, '10.15'

  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  s.vendored_libraries = 'Libraries/libqdrant_edge_flutter.a'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
