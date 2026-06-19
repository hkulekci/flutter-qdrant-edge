#
# iOS side of the qdrant_edge_flutter FFI plugin.
#
# The native code is a Rust staticlib packaged as an xcframework by
# scripts/build-ios.sh. We vendor it and force-load it so its C symbols
# survive into the final app binary — Dart resolves them at runtime via
# DynamicLibrary.process().
#
Pod::Spec.new do |s|
  s.name             = 'qdrant_edge_flutter'
  s.version          = '0.1.0'
  s.summary          = 'On-device vector search for Flutter (qdrant-edge + BM25).'
  s.description      = <<-DESC
On-device vector search powered by the qdrant-edge Rust crate, with built-in
BM25 text embedding. No model download, no network.
                       DESC
  s.homepage         = 'https://qdrant.tech/edge/'
  s.license          = { :type => 'Apache-2.0' }
  s.author           = { 'Your Org' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '13.0'

  # A Flutter FFI plugin still needs at least one source file for the pod.
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'

  # Prebuilt Rust engine as a self-contained DYNAMIC framework that exports only
  # the qe_* C ABI (zstd/lz4 stay private inside it). Named differently from the
  # pod to avoid "multiple commands produce" under use_frameworks!. Being dynamic
  # also isolates it from static-binary pods (MediaPipe/TFLite via flutter_gemma):
  # no symbol stripping, no duplicate-symbol clashes. Dart resolves qe_* at
  # runtime via DynamicLibrary.process() (the framework auto-loads with the app).
  s.vendored_frameworks = 'Frameworks/QdrantEdgeFFI.xcframework'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
  }
end
